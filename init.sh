#!/bin/bash

read -p "Enter SQL Server host (default: localhost): " SERVER
SERVER=${SERVER:-localhost}

read -p "Enter SQL Server user: " USER

read -s -p "Enter SQL Server password: " PASSWORD
echo

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

list_users_by_database_interactive() {
  echo "Enter database name:"
  read dbname
  list_users_by_database "$dbname"
}

list_all_users_in_all_databases_loop() {
  for DATABASE_NAME in $(get_databases_names); do
    echo "[ $DATABASE_NAME ]"
    list_users_by_database $DATABASE_NAME
  done
}

LIST_ADMINS_QUERY="
    SET NOCOUNT ON;
    SELECT username FROM users WHERE username LIKE '%admin%';
  "

list_admins() {
  local DATABASE_NAME=$1
  execute_query "$LIST_ADMINS_QUERY" -d "$DATABASE_NAME" -s" | " -W -h-1
}

list_all_admins() {
  for DATABASE_NAME in $(get_databases_names); do
    echo "[ $DATABASE_NAME ]"
    list_admins "$DATABASE_NAME"
  done
}

change_admin_passwords() {
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

  for DATABASE_NAME in $(get_databases_names); do
    echo "[ $DATABASE_NAME ] Changing admin passwords..."
    ADMIN_USERS=$(execute_query "$LIST_ADMINS_QUERY" -d "$DATABASE_NAME" -h -1 -W)

    if [[ -z "$ADMIN_USERS" ]]; then
      echo "No admins found in $DATABASE_NAME"
      continue
    fi

    mkdir -p users
    OUTPUT_FILE="./users/${DATABASE_NAME}_updated.txt"
    TEMP_FILE=$(mktemp)

    {
      echo "### Password update at $TIMESTAMP"
      while IFS= read -r ADMIN_USERNAME; do
        NEW_PASSWORD=$(generate_random_string 10)
        NEW_PASSWORD_HASH=$(echo -n "$NEW_PASSWORD" | md5sum | cut -d ' ' -f1)

        UPDATE_QUERY="
          SET NOCOUNT ON;
          UPDATE users
          SET password_md5 = '$NEW_PASSWORD_HASH'
          WHERE username = '$ADMIN_USERNAME';
        "

        execute_query "$UPDATE_QUERY" -d "$DATABASE_NAME"
        echo "$ADMIN_USERNAME:$NEW_PASSWORD:$NEW_PASSWORD_HASH"
        echo "Updated admin: $ADMIN_USERNAME in $DATABASE_NAME"
      done <<<"$ADMIN_USERS"
      echo
    } >"$TEMP_FILE"

    if [[ -f "$OUTPUT_FILE" ]]; then
      cat "$TEMP_FILE" "$OUTPUT_FILE" >"${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
    else
      mv "$TEMP_FILE" "$OUTPUT_FILE"
    fi

    echo "Passwords updated and prepended to $OUTPUT_FILE"
  done

  echo "All admin passwords updated."
}

verify_user_password() {
  local DATABASE_NAME=$1
  local USERNAME=$2
  local PASSWORD_INPUT=$3

  local PASSWORD_INPUT_HASH
  PASSWORD_INPUT_HASH=$(echo -n "$PASSWORD_INPUT" | md5sum | cut -d ' ' -f1)

  local CHECK_PASSWORD_QUERY="
    SET NOCOUNT ON;
    SELECT COUNT(*) FROM users
    WHERE username = '$USERNAME' AND password_md5 = '$PASSWORD_INPUT_HASH';
  "

  local RESULT
  RESULT=$(execute_query "$CHECK_PASSWORD_QUERY" -d "$DATABASE_NAME" -h -1 -W)

  if [[ "$RESULT" == "1" ]]; then
    echo "Password is correct for user [$USERNAME] in database [$DATABASE_NAME]"
    return 0
  else
    echo "Incorrect password for user [$USERNAME] in database [$DATABASE_NAME]"
    return 1
  fi
}

check_password_interactively() {
  echo -n "Enter database name: "
  read db

  echo -n "Enter username: "
  read username

  echo -n "Enter password: "
  read -s password
  echo

  verify_user_password "$db" "$username" "$password"
}

interactive_menu() {
  local options=(
    "Create 50 databases"
    "Create users table in all databases"
    "Insert 5 users per database"
    "List users by database"
    "List all users from all databases"
    "List all admins"
    "Change all admins passwords"
    "Check password for a user"
    "Exit"
  )

  local actions=(
    "create_databases_loop"
    "create_users_table_loop"
    "insert_users_in_all_databases_loop"
    "list_users_by_database_interactive"
    "list_all_users_in_all_databases_loop"
    "list_all_admins"
    "change_admin_passwords"
    "check_password_interactively"
    "exit"
  )

  local selected=0
  local num_options=${#options[@]}

  while true; do
    clear
    echo -e "Select: "
    for i in "${!options[@]}"; do
      if [ "$i" -eq "$selected" ]; then
        echo -e "> \e[32m${options[$i]}\e[0m"
      else
        echo "  ${options[$i]}"
      fi
    done

    # Read key press
    IFS= read -rsn1 key
    if [[ $key == $'\x1b' ]]; then
      read -rsn2 key2
      key+="$key2"
    fi

    case "$key" in
    $'\x1b[A' | k) # Up arrow or k
      ((selected--))
      ((selected < 0)) && selected=$((num_options - 1))
      ;;
    $'\x1b[B' | j) # Down arrow or j
      ((selected++))
      ((selected >= num_options)) && selected=0
      ;;
    "") # Enter
      clear
      echo "Executing: ${options[$selected]}"
      "${actions[$selected]}"
      echo
      echo "Press Enter to continue..."
      read
      ;;
    q)
      echo "Exiting..."
      break
      ;;
    esac
  done
}

interactive_menu
