# Database Access Troubleshooting Guide

## 🚨 Error: SQLSTATE[HY000] [1045] Access denied for user

Error ini terjadi ketika Laravel tidak bisa mengakses database MySQL dengan kredensial yang diberikan.

### 🔍 Penyebab Umum:

1. **Sistem belum di-setup dengan benar**
2. **Database user tidak ada atau password salah**
3. **MySQL service tidak berjalan**
4. **File konfigurasi app tidak ada**
5. **Permissions MySQL user tidak tepat**

### 🛠️ Solusi Step-by-Step:

#### 1. Cek Status MySQL

```bash
# Cek apakah MySQL berjalan
sudo systemctl status mysql

# Jika tidak berjalan, start MySQL
sudo systemctl start mysql
sudo systemctl enable mysql
```

#### 2. Gunakan Database Commands di install.sh

Database troubleshooting sudah terintegrasi dalam install.sh:

```bash
# Lihat status MySQL
sudo ./install.sh db:status

# List semua apps dan status database
sudo ./install.sh db:list

# Cek database access untuk app tertentu
sudo ./install.sh db:check web_sam

# Fix database access untuk app tertentu
sudo ./install.sh db:fix web_sam

# Reset database untuk app tertentu (HATI-HATI: akan hapus semua data)
sudo ./install.sh db:reset web_sam
```

#### 3. Manual Troubleshooting

Jika script tidak membantu, lakukan manual troubleshooting:

```bash
# 1. Cek apakah sistem sudah di-setup
sudo ls -la /root/.mysql_credentials

# 2. Cek apakah app config ada
sudo ls -la /etc/laravel-apps/web_sam.conf

# 3. Jika config ada, load dan cek database
sudo cat /etc/laravel-apps/web_sam.conf

# 4. Test koneksi database manual
mysql -u web_sam_user -p web_sam_db
```

#### 4. Setup Ulang Sistem (Jika Diperlukan)

Jika sistem belum di-setup:

```bash
# Setup sistem dari awal
sudo ./install.sh setup

# Setelah setup, install app
./install.sh install web_sam example.com https://github.com/user/repo.git
```

#### 5. Recreate Database Manual

Jika perlu membuat database manual:

```bash
# Masuk ke MySQL sebagai root
sudo mysql -u root -p

# Buat database dan user
CREATE DATABASE `web_sam_db`;
CREATE USER 'web_sam_user'@'localhost' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON `web_sam_db`.* TO 'web_sam_user'@'localhost';
FLUSH PRIVILEGES;
```

### 📋 Checklist Troubleshooting:

- [ ] MySQL service berjalan
- [ ] File `/root/.mysql_credentials` ada
- [ ] File `/etc/laravel-apps/web_sam.conf` ada
- [ ] Database `web_sam_db` ada di MySQL
- [ ] User `web_sam_user` ada di MySQL
- [ ] User memiliki permissions ke database
- [ ] File `.env` di app directory memiliki kredensial yang benar

### 🔧 Common Commands:

```bash
# Restart MySQL
sudo systemctl restart mysql

# Cek MySQL error log
sudo tail -f /var/log/mysql/error.log

# Cek Laravel log
tail -f /opt/laravel-apps/web_sam/storage/logs/laravel.log

# Test database connection dari Laravel
cd /opt/laravel-apps/web_sam
php artisan tinker
>>> DB::connection()->getPdo();
```

### 📱 Contoh Konfigurasi yang Benar:

**File: `/etc/laravel-apps/web_sam.conf`**
```bash
APP_NAME=web_sam
APP_DIR=/opt/laravel-apps/web_sam
DOMAIN=example.com
DB_NAME=web_sam_db
DB_USER=web_sam_user
DB_PASS=generated_secure_password
GITHUB_REPO=https://github.com/user/repo.git
```

**File: `/opt/laravel-apps/web_sam/.env`**
```bash
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=web_sam_db
DB_USERNAME=web_sam_user
DB_PASSWORD=generated_secure_password
```

### 🚨 Emergency Recovery:

Jika semua gagal, lakukan recovery:

```bash
# 1. Backup data penting (jika ada)
sudo mysqldump -u root -p web_sam_db > backup.sql

# 2. Reset database completely
sudo ./install.sh db:reset web_sam

# 3. Restore data (jika ada backup)
mysql -u web_sam_user -p web_sam_db < backup.sql
```

### 📞 Bantuan Lebih Lanjut:

Jika masih bermasalah, jalankan:

```bash
# Debug lengkap
./install.sh debug web_sam

# Atau debug sistem
./install.sh debug
```

Dan berikan output dari command tersebut untuk analisis lebih lanjut. 