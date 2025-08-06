#!/bin/bash

SERVER="localhost"
USER="SA"
PASSWORD="Strong!Pass123"

CREATE_USER_TABLE_QUERY="
  IF OBJECT_ID('users', 'U') IS NOT NULL DROP TABLE users;
  CREATE TABLE users (
    id INT PRIMARY KEY IDENTITY(1,1),
    username NVARCHAR(100),
    password_md5 CHAR(32),
  );
  "

GET_DATABASES_NAMES="
 SET NOCOUNT ON;
 SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb');
"

execute_query() {
  local QUERY=$1
  shift

  if [[ -z "$QUERY" ]]; then
    echo "Warning: empty query, skipping execution."
    return 1
  fi

  sqlcmd -S "$SERVER" -U "$USER" -P "$PASSWORD" "$@" -Q "$QUERY"
}

create_database() {
  local DATABASE_NAME=$1
  execute_query "CREATE DATABASE [$DATABASE_NAME]"
}

create_user_table() {
  execute_query "$CREATE_USER_TABLE_QUERY"
}

get_databases_names() {
  DATABASES=$(execute_query "$GET_DATABASES_NAMES" -h -1 -W)
  echo $DATABASES
}

create_databases_loop() {
  for i in $(seq 1 50); do
    local DATABASE_NAME="db$i"
    echo "Creating database: $DATABASE_NAME"
    create_database $DATABASE_NAME
  done
  echo "All databases created."
}

create_users_table_loop() {
  for DATABASE_NAME in $(get_databases_names); do
    execute_query "$CREATE_USER_TABLE_QUERY" -d "$DATABASE_NAME"
    echo "Table [users] created on $DATABASE_NAME"
  done
  echo "Table users created on all databases."
}

generate_random_string() {
  tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$1"
}

insert_five_random_users() {
  local DATABASE_TO_INSERT=$1
  local OUTPUT_FILE="./users/${DATABASE_TO_INSERT}.txt"
  mkdir -p users
  >"$OUTPUT_FILE"

  for user in $(seq 1 5); do
    if [ "$user" -eq 1 ]; then
      USERNAME=admin_$(generate_random_string 4)
    else
      USERNAME=user_$(generate_random_string 6)
    fi

    PASSWORD_PLAIN=$(generate_random_string 10)
    PASSWORD_HASH=$(echo -n "$PASSWORD_PLAIN" | md5sum | cut -d ' ' -f1)
    CREDENTIALS="$USERNAME:$PASSWORD_PLAIN:$PASSWORD_HASH"
    echo "[$DATABASE_TO_INSERT] Inserting credentials: $CREDENTIALS"
    echo "$CREDENTIALS" >>"$OUTPUT_FILE"

    INSERT_USER_QUERY="
      SET NOCOUNT ON;
      INSERT INTO users (username, password_md5) VALUES ('$USERNAME', '$PASSWORD_HASH');
    "

    execute_query "$INSERT_USER_QUERY" -d "$DATABASE_TO_INSERT"
  done
}

insert_users_in_all_databases_loop() {
  for DATABASE_NAME in $(get_databases_names); do
    insert_five_random_users "$DATABASE_NAME"
  done
  echo "Five users inserted in all databases."
}

list_users_by_database() {
  local DATABASE_TO_INSERT=$1
  LIST_USERS_QUERY="
    SET NOCOUNT ON;
    SELECT id, username FROM users;
  "
  execute_query "$LIST_USERS_QUERY" -d "$DATABASE_TO_INSERT" -s" " -W -h-1
}

list_all_users_in_all_databases_loop() {
  for DATABASE_NAME in $(get_databases_names); do
    echo "[ $DATABASE_NAME ]"
    list_users_by_database $DATABASE_NAME
  done
}

list_admins() {
  local DATABASE_NAME=$1
  LIST_ADMINS_QUERY="
    SET NOCOUNT ON;
    SELECT id, username FROM users WHERE username LIKE '%admin%';
  "
  execute_query "$LIST_ADMINS_QUERY" -d "$DATABASE_NAME" -s" | " -W -h-1
}

list_all_admins() {
  echo "[ $DATABASE_NAME ]"
  for DATABASE_NAME in $(get_databases_names); do
    list_admins "$DATABASE_NAME"
  done
}
