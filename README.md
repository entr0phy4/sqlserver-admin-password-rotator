# SQL Server User Management Script

This Bash script automates the creation and management of SQL Server databases, user tables, and user credentials. It also supports admin password rotation and password verification.

## 🔧 Requirements

- **SQL Server** running locally or remotely.
- [`sqlcmd`](https://learn.microsoft.com/en-us/sql/tools/sqlcmd-utility?view=sql-server-ver16) command-line tool installed and available in your `PATH`.
- Linux/Unix system with Bash.
- `md5sum` for password hashing.

---

## 📂 Features

| Feature                               | Description                                                                 |
|--------------------------------------|-----------------------------------------------------------------------------|
| Create 50 databases                  | Databases named `db1` to `db50`.                                            |
| Create users table                   | Creates a `users` table in each database with `username` and MD5 password. |
| Insert 5 users per database          | One admin (`admin_XXXX`) and four regular users with random credentials.   |
| Log credentials per database         | Plaintext and hashed passwords are stored in `./users/<database>.txt`.     |
| Change all admin passwords           | Randomizes all admin passwords, prepends logs to `./users/<database>_updated.txt`. |
| Password verification                | Check if a password is correct for a given user in a specific DB.          |
| Interactive terminal menu            | Navigate with arrow keys or `j`/`k`, press enter to execute.               |

---

## 🚀 Usage

### 1. Start the Script

```bash
chmod +x manage_sql_users.sh
./manage_sql_users.sh
