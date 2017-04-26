#!/bin/bash
# Copyright (c) Microsoft Corporation. All Rights Reserved.
# Licensed under the MIT license. See LICENSE file on the project webpage for details.

set -x

# argument defaults
EDX_ROLE=""
DEPLOYMENT_ENV="dev"
ACCESS_TOKEN=""
CRON_MODE=0
TARGET_FILE=""

# Oxa Tools
# Settings for the OXA-Tools public repository 
OXA_TOOLS_PUBLIC_GITHUB_ACCOUNTNAME="Microsoft"
OXA_TOOLS_PUBLIC_GITHUB_PROJECTNAME="oxa-tools"
OXA_TOOLS_PUBLIC_GITHUB_PROJECTBRANCH="oxa/fic.search"

# this is the operational branch for the OXA_TOOLS public git project
OXA_TOOLS_VERSION=""

# EdX Configuration
# There are cases where we want to override the edx-configuration repository itself
EDX_CONFIGURATION_PUBLIC_GITHUB_ACCOUNTNAME="Microsoft"
EDX_CONFIGURATION_PUBLIC_GITHUB_PROJECTNAME="edx-configuration"
EDX_CONFIGURATION_PUBLIC_GITHUB_PROJECTBRANCH="oxa/master.search"

# this is the operational branch for the EDX_CONFIGURATION public git project
CONFIGURATION_VERSION=""

# EdX Platform
# There are cases where we want to override the edx-platform repository itself
EDX_PLATFORM_PUBLIC_GITHUB_ACCOUNTNAME="Microsoft"
EDX_PLATFORM_PUBLIC_GITHUB_PROJECTNAME="edx-platform"
EDX_PLATFORM_PUBLIC_GITHUB_PROJECTBRANCH="oxa/master.fic"

# EdX Theme
# There are cases where we want to override the edx-platform repository itself
EDX_THEME_PUBLIC_GITHUB_ACCOUNTNAME="Microsoft"
EDX_THEME_PUBLIC_GITHUB_PROJECTNAME="edx-theme"
EDX_THEME_PUBLIC_GITHUB_PROJECTBRANCH="pilot"
EDX_THEME_NAME="default"

# EdX Ansible
# There are cases where we want to override the edx\ansible repository itself
ANSIBLE_PUBLIC_GITHUB_ACCOUNTNAME="edx"
ANSIBLE_PUBLIC_GITHUB_PROJECTNAME="ansible"
ANSIBLE_PUBLIC_GITHUB_PROJECTBRANCH="master"

# MISC
EDX_VERSION="master"
#FORUM_VERSION="mongoid5-release"
FORUM_VERSION="open-release/ficus.master"

# script used for triggering background installation (setup in cron)
CRON_INSTALLER_SCRIPT=""

# SMTP / Mailer parameters
CLUSTER_ADMIN_EMAIL=""
MAIL_SUBJECT="OXA Bootstrap"
NOTIFICATION_MESSAGE=""
SECONDARY_LOG="/var/log/bootstrap.csx.log"
PRIMARY_LOG="/var/log/bootstrap.log"

display_usage() {
  echo "Usage: $0 -a|--access_token {access token} -v|--version {oxa-tools-config version} [-r|--role {jb|vmss|mongo|mysql|edxapp|fullstack}] [-e|--environment {dev|bvt|int|prod}] [--cron] --keyvault-name {azure keyvault name} --aad-webclient-id {AAD web application client id} --aad-webclient-appkey {AAD web application client key} --aad-tenant-id {AAD Tenant to authenticate against} --azure-subscription-id {Azure subscription Id}"
  exit 1
}

parse_args() 
{
    while [[ "$#" -gt 0 ]]
    do
        arg_value="${2}"
        shift_once=0

        if [[ "${arg_value}" =~ "--" ]]; 
        then
            arg_value=""
            shift_once=1
        fi

         # Log input parameters to facilitate troubleshooting
        echo "Option '${1}' set with value '"${arg_value}"'"

        case "$1" in
          -r|--role)
            EDX_ROLE="${arg_value,,}" # convert to lowercase
            if ! is_valid_arg "jb vmss mongo mysql edxapp fullstack" $EDX_ROLE; then
              echo "Invalid role specified\n"
              display_usage
            fi
            ;;
          -e|--environment)
            DEPLOYMENT_ENV="${arg_value,,}" # convert to lowercase
            if ! is_valid_arg "dev bvt int prod" $DEPLOYMENT_ENV; then
              echo "Invalid environment specified\n"
              display_usage
            fi
            ;;
          # For fullstack deployments
          -a|--access_token)
            ACCESS_TOKEN="${arg_value}"
            ;;
          --cron)
            CRON_MODE=1
            ;;
          --oxatools-public-github-accountname)
            OXA_TOOLS_PUBLIC_GITHUB_ACCOUNTNAME="${arg_value}"
            ;;
          --oxatools-public-github-projectname)
            OXA_TOOLS_PUBLIC_GITHUB_PROJECTNAME="${arg_value}"
            ;;
          --oxatools-public-github-projectbranch)
            OXA_TOOLS_PUBLIC_GITHUB_PROJECTBRANCH="${arg_value}"
            ;;
          --edxconfiguration-public-github-accountname)
            EDX_CONFIGURATION_PUBLIC_GITHUB_ACCOUNTNAME="${arg_value}"
            ;;
          --edxconfiguration-public-github-projectname)
            EDX_CONFIGURATION_PUBLIC_GITHUB_PROJECTNAME="${arg_value}"
            ;;
          --edxconfiguration-public-github-projectbranch)
            EDX_CONFIGURATION_PUBLIC_GITHUB_PROJECTBRANCH="${arg_value}"
            ;;
          --edxplatform-public-github-accountname)
            EDX_PLATFORM_PUBLIC_GITHUB_ACCOUNTNAME="${arg_value}"
            ;;
          --edxplatform-public-github-projectname)
            EDX_PLATFORM_PUBLIC_GITHUB_PROJECTNAME="${arg_value}"
            ;;
          --edxplatform-public-github-projectbranch)
            EDX_PLATFORM_PUBLIC_GITHUB_PROJECTBRANCH="${arg_value}"
            ;;
          --edxtheme-public-github-accountname)
            EDX_THEME_PUBLIC_GITHUB_ACCOUNTNAME="${arg_value}"
            ;;
          --edxtheme-public-github-projectname)
            EDX_THEME_PUBLIC_GITHUB_PROJECTNAME="${arg_value}"
            ;;
          --edxtheme-public-github-projectbranch)
            EDX_THEME_PUBLIC_GITHUB_PROJECTBRANCH="${arg_value}"
            ;;
          --ansible-public-github-accountname)
            ANSIBLE_PUBLIC_GITHUB_ACCOUNTNAME="${arg_value}"
            ;;
          --ansible-public-github-projectname)
            ANSIBLE_PUBLIC_GITHUB_PROJECTNAME="${arg_value}"
            ;;
          --ansible-public-github-projectbranch)
            ANSIBLE_PUBLIC_GITHUB_PROJECTBRANCH="${arg_value}"
            ;;
          --edxversion)
            EDX_VERSION="${arg_value}"
            ;;
           --forumversion)
            FORUM_VERSION="${arg_value}"
            ;;
          --installer-script-path)
            CRON_INSTALLER_SCRIPT="${arg_value}"
            ;;
          --cluster-admin-email)
            CLUSTER_ADMIN_EMAIL="${arg_value}"
            ;;
          --cluster-name)
            CLUSTER_NAME="${arg_value}"
            MAIL_SUBJECT="${MAIL_SUBJECT} - ${arg_value,,}"
            ;;
          *)
            # Unknown option encountered
            echo "Option '${BOLD}$1${NORM} ${arg_value}' not allowed."
            display_usage
            ;;
        esac

        shift # past argument or value

        if [ $shift_once -eq 0 ]; 
        then
            shift # past argument or value
        fi

    done
}

##
## Check if bootstrap needs to be run for the specified role
##
get_bootstrap_status()
{
    # this determination is role-dependent
    #TODO: setup a more elaborate crumb system

    # we will perform a presence test for a /var/log/bootstrap-$EDX_ROLE.log
    # the expectation is that when the bootstrap script completes successfully, this file will be created

    # 0 - Proceed with setup
    # 1 - Wait on backend
    # 2 - Bootstrap done
    # 3 - Bootstrap in progress

    # by default we assume, bootstrap is needed
    PRESENCE=0

    # check if the bootstrap is finished
    if [ -e $TARGET_FILE ];
    then
        # The crumb exists:: bootstrap is done
        PRESENCE=2
    else
        # check if there is an ongoing execution
        if [ "$EDX_ROLE" == "vmss" ];
        then
            # Source the settings
            # Moving source here reduces the noise in the logs
            source $OXA_ENV_FILE

            # apply the overridesm
            if [[ -f $OXA_ENV_OVERRIDE_FILE ]]; then
                source $OXA_ENV_OVERRIDE_FILE
            fi

            # The crumb doesn't exist:: we need to execute boostrap
            # For VMSS role, we have to wait on the backend Mysql bootstrap operation
            # The Mysql master is known. This is the one we really care about. If it is up, we will call backend bootstrap done
            # It is expected that the client tools are already installed
            #echo "Testing connection to edxapp database on '${MYSQL_MASTER_IP}'"
            AUTH_USER_COUNT=`mysql -u $MYSQL_ADMIN_USER -p$MYSQL_ADMIN_PASSWORD -h $MYSQL_MASTER_IP -s -N -e "use edxapp; select count(*) from auth_user;"`
            if [[ $? -ne 0 ]];
            then
                #echo "Connection test failed. Keeping holding pattern for VMSS bootstrap"
                # The crumb doesn't exist:: we need to execute boostrap, but we have unmet dependency (wait)
                PRESENCE=1
            fi
        fi
    fi
    echo $PRESENCE
}

setup_overrides_file()
{
    log "Setting up deployment overrides file at $OXA_ENV_OVERRIDE_FILE"

    # in order to support deployment-time configuration bootstrap (specifying repository & branch for the key bits: Oxa-Tools, EdX Platform, EdX Theme, Edx Configuration)
    # we have to allow settings for each of these repositories to override whatever existing settings there are
    EDX_CONFIGURATION_REPO="https://github.com/${EDX_CONFIGURATION_PUBLIC_GITHUB_ACCOUNTNAME}/${EDX_CONFIGURATION_PUBLIC_GITHUB_PROJECTNAME}.git"
    EDX_PLATFORM_REPO="https://github.com/${EDX_PLATFORM_PUBLIC_GITHUB_ACCOUNTNAME}/${EDX_PLATFORM_PUBLIC_GITHUB_PROJECTNAME}.git"
    EDX_THEME_REPO="https://github.com/${EDX_THEME_PUBLIC_GITHUB_ACCOUNTNAME}/${EDX_THEME_PUBLIC_GITHUB_PROJECTNAME}.git"
    EDX_ANSIBLE_REPO="https://github.com/${ANSIBLE_PUBLIC_GITHUB_ACCOUNTNAME}/${ANSIBLE_PUBLIC_GITHUB_PROJECTNAME}.git"

    # setup the deployment overrides (for debugging and deployment-time control of repositories used)
    setup_deployment_overrides $OXA_ENV_OVERRIDE_FILE $OXA_TOOLS_PUBLIC_GITHUB_PROJECTBRANCH $EDX_CONFIGURATION_REPO $EDX_CONFIGURATION_PUBLIC_GITHUB_PROJECTBRANCH $EDX_PLATFORM_REPO $EDX_PLATFORM_PUBLIC_GITHUB_PROJECTBRANCH $EDX_THEME_REPO $EDX_THEME_PUBLIC_GITHUB_PROJECTBRANCH $EDX_VERSION $FORUM_VERSION $EDX_ANSIBLE_REPO $ANSIBLE_PUBLIC_GITHUB_PROJECTBRANCH
}

##
## Role-independent OXA environment bootstrap
##
setup()
{
    # There is an implicit pre-requisite for the GIT client to be installed. 
    # This is already handled in the calling script
  
    # populate the deployment environment
    source $OXA_ENV_FILE
    export $(sed -e 's/#.*$//' $OXA_ENV_FILE | cut -d= -f1)

    # apply the overrides
    if [[ -f $OXA_ENV_OVERRIDE_FILE ]]; then
        source $OXA_ENV_OVERRIDE_FILE
    fi

    export $(sed -e 's/#.*$//' $OXA_ENV_OVERRIDE_FILE | cut -d= -f1)
    export ANSIBLE_REPO=$EDX_ANSIBLE_REPO
    export ANSIBLE_VERSION=$EDX_ANSIBLE_PUBLIC_GITHUB_PROJECTBRANCH
  
    # Sync public repositories using utilities.sh
    sync_repo $OXA_TOOLS_REPO $OXA_TOOLS_VERSION $OXA_TOOLS_PATH
    sync_repo $CONFIGURATION_REPO $CONFIGURATION_VERSION $CONFIGURATION_PATH

    # setup theme
    #THEME_PATH="${OXA_PATH}/${EDX_THEME_PUBLIC_GITHUB_PROJECTNAME}"
    #sync_repo $EDX_THEME_REPO $EDX_THEME_PUBLIC_GITHUB_PROJECTBRANCH "${THEME_PATH}/${EDX_THEME_NAME}"
    #ln -s $THEME_PATH /edx/app/edxapp/themes
    #chown -R edxapp:edxapp $THEME_PATH

    # run edx bootstrap and install requirements
    cd $CONFIGURATION_PATH
    ANSIBLE_BOOTSTRAP_SCRIPT=util/install/ansible-bootstrap.sh

    # in order to support retries, we need to clean the temporary folder where the ansible bootstrap script clones the repository
    TEMP_CONFIGURATION_PATH=/tmp/configuration
    if [[ -d $TEMP_CONFIGURATION_PATH ]]; then
        echo "Removing the temporary configuration path at $TEMP_CONFIGURATION_PATH"
        rm -rf $TEMP_CONFIGURATION_PATH
    else
        echo "Skipping clean up of $TEMP_CONFIGURATION_PATH"
    fi

    bash $ANSIBLE_BOOTSTRAP_SCRIPT
    exit_on_error "Failed executing $ANSIBLE_BOOTSTRAP_SCRIPT"

    pip install -r requirements.txt
    exit_on_error "Failed pip-installing EdX requirements"

    # fix OXA environment ownership
    chown -R $ADMIN_USER:$ADMIN_USER $OXA_PATH

    # aggregate edx configuration with deployment environment expansion
    # warning: beware of yaml variable dependencies due to order of aggregation
    echo "---" > $OXA_PLAYBOOK_CONFIG
    for config in $OXA_TOOLS_PATH/config/$TEMPLATE_TYPE/*.yml $OXA_TOOLS_PATH/config/*.yml; do
        sed -e "s/%%\([^%]*\)%%/$\{\\1\}/g" -e "s/^---.*$//g" $config | envsubst >> $OXA_PLAYBOOK_CONFIG
    done
}

update_stamp_jb() 
{
    SUBJECT="${MAIL_SUBJECT} - EdX Database (Mysql) Setup Failed"

    # edx playbooks - mysql and memcached
    $ANSIBLE_PLAYBOOK -i $MYSQL_MASTER_IP, $OXA_SSH_ARGS -e@$OXA_PLAYBOOK_CONFIG edx_mysql.yml
    exit_on_error "Execution of edX MySQL playbook failed (Stamp JB)" 1 "${SUBJECT}" "${CLUSTER_ADMIN_EMAIL}" "${PRIMARY_LOG}" "${SECONDARY_LOG}"

    # minimize tags? "install:base,install:system-requirements,install:configuration,install:app-requirements,install:code"
    $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG edx_sandbox.yml -e "migrate_db=yes" --tags "edxapp-sandbox,install,migrate"
    exit_on_error "Execution of edX MySQL migrations failed" 1 "${SUBJECT}" "${CLUSTER_ADMIN_EMAIL}" "${PRIMARY_LOG}" "${SECONDARY_LOG}"
  
    # oxa playbooks - mongo (enable when customized) and mysql
    #$ANSIBLE_PLAYBOOK -i ${CLUSTERNAME}mongo1, $OXA_SSH_ARGS -e@$OXA_PLAYBOOK_CONFIG $OXA_PLAYBOOK_ARGS $OXA_PLAYBOOK --tags "mongo"
    #exit_on_error "Execution of OXA Mongo playbook failed"

    $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG $OXA_PLAYBOOK_ARGS $OXA_PLAYBOOK --tags "mysql"
    exit_on_error "Execution of OXA MySQL playbook failed" 1 "${SUBJECT}" "${CLUSTER_ADMIN_EMAIL}" "${PRIMARY_LOG}" "${SECONDARY_LOG}"

    # if the Memcache Server is different than the Mysql Master server, we have to install memcache with default configs
    if [ "$MEMCACHE_SERVER_IP" != "$MYSQL_MASTER_IP" ];
    then
        log "Installing alternate Memcache"
        $ANSIBLE_PLAYBOOK -i $MEMCACHE_SERVER_IP, $OXA_SSH_ARGS -e@$OXA_PLAYBOOK_CONFIG $OXA_PLAYBOOK_ARGS $OXA_PLAYBOOK --tags "memcached"
        exit_on_error "Execution of OXA alternate memcache playbook task failed" 1 "${SUBJECT}" "${CLUSTER_ADMIN_EMAIL}" "${PRIMARY_LOG}" "${SECONDARY_LOG}"
    fi
}

update_stamp_vmss() 
{
    SUBJECT="${MAIL_SUBJECT} - EdX App (VMSS) Setup Failed"
    # edx playbooks - sandbox with remote mongo/mysql
    $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG edx_sandbox.yml -e "migrate_db=no" --skip-tags=demo_course
    exit_on_error "Execution of edX sandbox playbook failed" 1 "${SUBJECT}" "${CLUSTER_ADMIN_EMAIL}" "${PRIMARY_LOG}" "${SECONDARY_LOG}"
  
    # oxa playbooks
    $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG $OXA_PLAYBOOK_ARGS $OXA_PLAYBOOK --tags "edxapp"
    exit_on_error "Execution of OXA edxapp playbook failed" 1 "${SUBJECT}" "${CLUSTER_ADMIN_EMAIL}" "${PRIMARY_LOG}" "${SECONDARY_LOG}"
}

update_scalable_mongo() {
  # edx playbooks - mongo
  $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG edx_mongo.yml
  exit_on_error "Execution of edX Mongo playbook failed"

  # oxa playbooks - mongo (enable when customized)
  #$ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG $OXA_PLAYBOOK_ARGS $OXA_PLAYBOOK --tags "mongo"
  #exit_on_error "Execution of OXA Mongo playbook failed"
}

update_scalable_mysql() {
  # edx playbooks - mysql and memcached
  $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG edx_mysql.yml
  exit_on_error "Execution of edX MySQL playbook failed"
  # minimize tags? "install:base,install:system-requirements,install:configuration,install:app-requirements,install:code"
  $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG edx_sandbox.yml -e "migrate_db=yes" --tags "edxapp-sandbox,install,migrate"
  exit_on_error "Execution of edX MySQL migrations failed"

  # oxa playbooks - mysql
  $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG $OXA_PLAYBOOK_ARGS $OXA_PLAYBOOK --tags "mysql"
  exit_on_error "Execution of OXA MySQL playbook failed"
}

update_fullstack() {
  # edx playbooks - fullstack (single VM)
  $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG vagrant-fullstack.yml
  exit_on_error "Execution of edX fullstack playbook failed"

  # oxa playbooks - all (single VM)
  $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG $OXA_PLAYBOOK_ARGS $OXA_PLAYBOOK
  exit_on_error "Execution of OXA playbook failed"
}

update_devstack() {
  if ! id -u vagrant > /dev/null 2>&1; then
  # create required vagrant user account to avoid fatal error
    sudo adduser --disabled-password --gecos "" vagrant

    # set the vagrant password
    sudo usermod --password $(echo $VAGRANT_USER_PASSWORD | openssl passwd -1 -stdin) vagrant
  fi

  # create some required directories to avoid fatal errors
  if [ ! -d /edx/app/ecomworker ]; then
  sudo mkdir -p /edx/app/ecomworker
  fi

  if [ ! -d /home/vagrant/share_x11 ]; then
  sudo mkdir -p /home/vagrant/share_x11
  fi

  if [ ! -d /edx/app/ecommerce ]; then
    sudo mkdir -p /edx/app/ecommerce
  fi

  if [ ! -f /home/vagrant/.bashrc ]; then
  # create empty .bashrc file to avoid fatal error
  sudo touch /home/vagrant/.bashrc
  fi

  if $(stat -c "%U" /home/vagrant) != "vagrant"; then
    # Change the owner of the /home/vagrant folder and its subdirectories to the vagrant user account
    # to avoid an error in TASK: [local_dev | login share X11 auth to app users] related to file
    # "/home/vagrant/share_x11/share_x11.j2" msg: chown failed: failed to look up user vagrant
    sudo chown -hR vagrant /home/vagrant
  fi

  # edx playbooks - devstack (single VM)
  # Skip ecommerce for now since it isn't used and requires debugging
  $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG vagrant-devstack.yml --skip-tags="ecommerce,ecomworker"
  exit_on_error "Execution of edX devstack playbook failed"

  # oxa playbooks - all (single VM)
  $ANSIBLE_PLAYBOOK -i localhost, -c local -e@$OXA_PLAYBOOK_CONFIG $OXA_PLAYBOOK_ARGS $OXA_PLAYBOOK -e "edxrole=$EDX_ROLE"
  exit_on_error "Execution of OXA playbook failed"
}

###############################################
# START CORE EXECUTION
###############################################

# source our utilities for logging and other base functions (we need this staged with the installer script)
# the file needs to be first downloaded from the public repository
CURRENT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
UTILITIES_PATH=$CURRENT_PATH/../templates/stamp/utilities.sh

# check if the utilities file exists. If not, bail out.
if [[ ! -e $UTILITIES_PATH ]]; 
then  
    echo :"Utilities not present"
    exit 3
fi

# source the utilities now
source $UTILITIES_PATH

# Script self-idenfitication
print_script_header

parse_args $@ # pass existing command line arguments

##
## Execute role-independent OXA environment bootstrap
##
BOOTSTRAP_HOME=$(readlink -f $(dirname $0))
OXA_PATH="/oxa"

# OXA Tools
OXA_TOOLS_REPO="https://github.com/${OXA_TOOLS_PUBLIC_GITHUB_ACCOUNTNAME}/${OXA_TOOLS_PUBLIC_GITHUB_PROJECTNAME}.git"
OXA_TOOLS_PATH=$OXA_PATH/$OXA_TOOLS_PUBLIC_GITHUB_PROJECTNAME

# OXA Tools Config
OXA_TOOLS_CONFIG_PATH=$OXA_PATH/oxa-tools-config
OXA_ENV_PATH=$OXA_TOOLS_CONFIG_PATH/env/$DEPLOYMENT_ENV
OXA_ENV_FILE=$OXA_ENV_PATH/$DEPLOYMENT_ENV.sh
OXA_ENV_OVERRIDE_FILE="$BOOTSTRAP_HOME/overrides.sh"

# OXA Configuration
CONFIGURATION_PATH=$OXA_PATH/configuration
OXA_PLAYBOOK_CONFIG=$OXA_PATH/oxa.yml

# setup the installer path & key variables
INSTALLER_BASEPATH="${OXA_TOOLS_PATH}/scripts"

# create the overrides settings file
setup_overrides_file

##
## CRON CheckPoint
## We now have support for cron execution at x interval
## Given the possible execution frequency, we want to do the bare minimum
##

# setup crumbs for tracking purposes
TARGET_FILE=/var/log/bootstrap-$EDX_ROLE.log

if [ "$CRON_MODE" == "1" ];
then
    # turn off the debug messages since we have proper logging by now
    # set +x

    echo "Cron execution for ${EDX_ROLE} on ${HOSTNAME} detected."

    # check if we need to run the setup
    RUN_BOOTSTRAP=$(get_bootstrap_status)
    TIMESTAMP=`date +"%D %T"`

    case "$RUN_BOOTSTRAP" in
        "0")
            echo "${TIMESTAMP} : Bootstrap is not complete. Proceeding with setup..."
            ;;
        "1")
            echo "${TIMESTAMP} : Bootstrap is not complete. Waiting on backend bootstrap..."
            exit
            ;;
        "2")
            echo "${TIMESTAMP} : Bootstrap is complete."
            exit
            ;;
        "3")
            echo "${TIMESTAMP} : Bootstrap is in progress."
            exit
            ;;
    esac
fi

# Note when we started
log "Starting bootstrap of ${EDX_ROLE} on ${HOSTNAME}"

setup

##
## Execute role-based automation (edX and OXA playbooks)
## stamp note: assumes DB installations and SSH keys are already in place
##
PATH=$PATH:/edx/bin
ANSIBLE_PLAYBOOK=ansible-playbook
OXA_PLAYBOOK=$OXA_TOOLS_PATH/playbooks/oxa_configuration.yml
OXA_PLAYBOOK_ARGS="-e oxa_tools_path=$OXA_TOOLS_PATH -e oxa_tools_config_path=$OXA_TOOLS_CONFIG_PATH -e template_type=$TEMPLATE_TYPE"
OXA_SSH_ARGS="-u $ADMIN_USER --private-key=/home/$ADMIN_USER/.ssh/id_rsa"

# Fixes error: RPC failed; result=56, HTTP code = 0'
# fatal: The remote end hung up unexpectedly
git config --global http.postBuffer 1048576000

cd $CONFIGURATION_PATH/playbooks
case "$EDX_ROLE" in
  jb)
    update_stamp_jb
    ;;
  vmss)
    update_stamp_vmss
    ;;
  edxapp)
    # scalable and stamp vmss are equivalent; can combine vmss and edxapp once stamp is ready
    update_stamp_vmss
    ;;
  mongo)
    update_scalable_mongo
    ;;
  mysql)
    update_scalable_mysql
    ;;
  fullstack)
    update_fullstack
    ;;
  devstack)
    update_devstack
    ;;
  *)
    display_usage
    ;;
esac

# Note when we ended
# log a closing message and leave expected bread crumb for status tracking
log "Completed bootstrap of ${EDX_ROLE} on ${HOSTNAME}"

echo "Creating Phase 1 Crumb at '$TARGET_FILE''"
touch $TARGET_FILE

# remove the cron install job
if [[ -e $CRON_INSTALLER_SCRIPT ]]; 
then  
    log "Uninstalling cron job: Background Installer Script"
    crontab -l | grep -v "sudo bash $CRON_INSTALLER_SCRIPT" | crontab -

    rm $CRON_INSTALLER_SCRIPT
fi

# at this point, we have succeeded
if [ "$EDX_ROLE" == "jb" ] ; 
then
    NOTIFICATION_MESSAGE="Installation of the EDX Database was completed successfully."
elif [ "$EDX_ROLE" == "vmss" ] ;
then
    NOTIFICATION_MESSAGE="Installation of the EDX Application (VMSS) was completed successfully."
fi

log "${NOTIFICATION_MESSAGE}"
send_notification "${NOTIFICATION_MESSAGE}" "${MAIL_SUBJECT}" "${CLUSTER_ADMIN_EMAIL}"
exit 0
