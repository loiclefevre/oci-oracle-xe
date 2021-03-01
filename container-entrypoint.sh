#!/bin/bash
#
# Since: January, 2021
# Author: gvenzl
# Name: container-entrypoint.sh
# Description: The entrypoint script for the container
#
# Copyright 2021 Gerald Venzl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Exit on errors
# Great explanation on https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -Eeuo pipefail

# Stop container when SIGINT or SIGTERM is received
########### stop database helper function ############
function stop_database() {
   echo "CONTAINER: shutdown request received."
   echo "CONTAINER: shutting down database!"

   lsnrctl stop
   sqlplus -s / as sysdba <<EOF
      shutdown immediate;
      exit;
EOF
   echo "CONTAINER: stopping container."
}

# Retrieve value from ENV[_FILE] variable
# usage: file_env VARIABLE NAME [DEFAULT VALUE]
#    ie: file_env 'ORACLE_PASSWORD' 'example'
# (will allow for "$ORACLE_PASSWORD_FILE" to fill in the value of
#  "$ORACLE_PASSWORD" from a file, especially for container secrets feature)
file_env() {

  # Get name of variable
  local variable="${1}"
  # Get name of variable_FILE
  local file_variable="${variable}_FILE"

  # If both variable and file_variable are specified, throw error and abort
  if [ -n "${!variable:-}" ] && [ -n "${!file_variable:-}" ]; then
    echo "Both \$${variable} and \$${file_variable} are specified but are mutually exclusive."
    echo "Please specify only one of these variables."
    exit 1;
  fi;

  # Set value to default value, if any
  local value="${2:-}"

  # Read value of variable, if any
  if [ -n "${!variable:-}" ]; then
    value="${!variable}"
  # Read value of variable_FILE, if any
  elif [ -n "${!file_variable:-}" ]; then
    value="$(< "${!file_variable}")"
  fi

  export "${variable}"="${value}"
}

# Setup environment variables
function setup_env_vars() {

  declare -g DATABASE_ALREADY_EXISTS

  if [ -d "${ORACLE_BASE}/oradata/dbconfig/${ORACLE_SID}" ]; then
    DATABASE_ALREADY_EXISTS="true";
  else
    # Allow for ORACLE_PASSWORD and or ORACLE_PASSWORD_FILE
    file_env "ORACLE_PASSWORD"

    # Password is mandatory for first container start
    if [ -z "${ORACLE_PASSWORD:-}" ] && [ -z "${ORACLE_RANDOM_PASSWORD:-}" ]; then
      echo "Oracle Database SYS and SYSTEM passwords have to be specified at first database startup."
      echo "Please specify a password either via the \$ORACLE_PASSWORD variable, e.g. '-e ORACLE_PASSWORD=<password>'"
      echo "or set the \$ORACLE_RANDOM_PASSWORD environment variable to any value, e.g. '-e ORACLE_RANDOM_PASSWORD=yes'."
      exit 1;
    # ORACLE_PASSWORD and ORACLE_RANDOM_PASSWORD are mutually exclusive
    elif [ -n "${ORACLE_PASSWORD:-}" ] && [ -n "${ORACLE_RANDOM_PASSWORD:-}" ]; then
      echo "Both \$ORACLE_RANDOM_PASSWORD and \$ORACLE_PASSWORD[_FILE] are specified but are mutually exclusive."
      echo "Please specify only one of these variables."
      exit 1;
    fi;
  fi;
}

# Create dbconfig directory structure
function create_dbconfig() {

  if [ -f "${ORACLE_BASE}"/oradata/"${ORACLE_SID}".zip ]; then
     echo "CONTAINER: uncompressing database data files, please wait..."
     unzip "${ORACLE_BASE}"/oradata/"${ORACLE_SID}".zip -d "${ORACLE_BASE}"/oradata/ 1> /dev/null
     rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}".zip
  fi;

  mkdir -p "${ORACLE_BASE}/oradata/dbconfig/${ORACLE_SID}"

  mv "${ORACLE_HOME}"/dbs/spfile"${ORACLE_SID}".ora "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_HOME}"/dbs/orapw"${ORACLE_SID}" "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_HOME}"/network/admin/listener.ora "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_HOME}"/network/admin/tnsnames.ora "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_HOME}"/network/admin/sqlnet.ora "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  
  sym_link_dbconfig
}

# Remove the existing config files inside the image
function remove_config_files()  {
  
  if [ -f "${ORACLE_HOME}"/dbs/spfile"${ORACLE_SID}".ora ]; then
    rm "${ORACLE_HOME}"/dbs/spfile"${ORACLE_SID}".ora
  fi;

  if [ -f "${ORACLE_HOME}"/dbs/orapw"${ORACLE_SID}" ]; then
    rm "${ORACLE_HOME}"/dbs/orapw"${ORACLE_SID}"
  fi;

  if [ -f "${ORACLE_HOME}"/network/admin/listener.ora ]; then
    rm "${ORACLE_HOME}"/network/admin/listener.ora
  fi;

  if [ -f "${ORACLE_HOME}"/network/admin/tnsnames.ora ]; then
    rm "${ORACLE_HOME}"/network/admin/tnsnames.ora
  fi;

  if [ -f "${ORACLE_HOME}"/network/admin/sqlnet.ora ]; then
    rm "${ORACLE_HOME}"/network/admin/sqlnet.ora
  fi;
}

# Create symbolic links to dbconfig files
function sym_link_dbconfig() {

  if [ ! -L "${ORACLE_HOME}"/dbs/spfile"${ORACLE_SID}".ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/spfile"${ORACLE_SID}".ora "${ORACLE_HOME}"/dbs/spfile"${ORACLE_SID}".ora
  fi;
  
  if [ ! -L "${ORACLE_HOME}"/dbs/orapw"${ORACLE_SID}" ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/orapw"${ORACLE_SID}" "${ORACLE_HOME}"/dbs/orapw"${ORACLE_SID}"
  fi;
  
  if [ ! -L "${ORACLE_HOME}"/network/admin/listener.ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/listener.ora "${ORACLE_HOME}"/network/admin/listener.ora
  fi;

  if [ ! -L "${ORACLE_HOME}"/network/admin/tnsnames.ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/tnsnames.ora "${ORACLE_HOME}"/network/admin/tnsnames.ora
  fi;

  if [ ! -L "${ORACLE_HOME}"/network/admin/sqlnet.ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/sqlnet.ora "${ORACLE_HOME}"/network/admin/sqlnet.ora
  fi;

}

###########################
###########################
######### M A I N #########
###########################
###########################

# Set SIGINT & SIGTERM handlers
trap stop_database SIGINT SIGTERM

echo "CONTAINER: starting up..."

setup_env_vars

# If database does not yet exist, create directory structure
if [ -z "${DATABASE_ALREADY_EXISTS:-}" ]; then
  echo "CONTAINER: first database startup, initializing..."
  create_dbconfig
# Otherwise check that symlinks are in place
else
  echo "CONTAINER: database already initialized."
  remove_config_files
  sym_link_dbconfig
fi;

# Startup listener and database
echo "CONTAINER: starting up Oracle Database..."
lsnrctl start && \
sqlplus -s / as sysdba << EOF
  startup;
  exit;
EOF
echo ""

# Check whether database did come up successfully
if healthcheck.sh; then
  # Set Oracle password if it's the first DB startup
  if [ -z "${DATABASE_ALREADY_EXISTS:-}" ]; then
    echo "CONTAINER: Resetting SYS and SYSTEM passwords."
    # If password is specified
    if [ -n "${ORACLE_PASSWORD:-}" ]; then
      resetPassword "${ORACLE_PASSWORD}"
    # Generate random password
    elif [ -n "${ORACLE_RANDOM_PASSWORD:-}" ]; then
      RANDOM_PASSWORD=$(date +%s | sha256sum | base64 | head -c 8)
      resetPassword "${RANDOM_PASSWORD}"
      echo "############################################"
      echo "ORACLE PASSWORD FOR SYS AND SYSTEM: ${RANDOM_PASSWORD}"
      echo "############################################"
    # Should not happen unless script logic changes
    else
      echo "SCRIPT ERROR: Unspecified password!"
      echo "Please report a bug at https://github.com/gvenzl/oci-oracle-xe/issues with your environment details."
      exit 1;
    fi;
  else
    # Password was passed on for container start but DB is already initialized, ignoring.
    if [ -n "${ORACLE_PASSWORD:-}" ]; then
      echo "CONTAINER: WARNING: \$ORACLE_PASSWORD has been specified but the database is already initialized. The password will be ignored."
      echo "CONTAINER: WARNING: If you want to reset the password, please run the resetPassword command, e.g. 'docker|podman exec <container name|id> resetPassword <your password>'."
    fi;
  fi;
  echo ""
  echo "#########################"
  echo "DATABASE IS READY TO USE!"
  echo "#########################"
  echo ""
  echo "##################################################################"
  echo "CONTAINER: The following output is now from the alert_${ORACLE_SID}.log file:"
  echo "##################################################################"
else
  echo "############################################"
  echo "DATABASE STARTUP FAILED!"
  echo "CHECK LOG OUTPUT ABOVE FOR MORE INFORMATION!"
  echo "############################################"
  exit 1;
fi;

tail -f "${ORACLE_BASE}"/diag/rdbms/*/"${ORACLE_SID}"/trace/alert_"${ORACLE_SID}".log &
childPID=$!
wait ${childPID}
