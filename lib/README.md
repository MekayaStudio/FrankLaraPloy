# Struktur Library FrankLaraPloy

Direktori `lib` telah direorganisasi untuk memberikan struktur yang lebih terorganisir dan mudah dipahami.

## Struktur Direktori

```
lib/
├── core/           # Logika bisnis utama aplikasi
├── modules/        # Driver/plugin untuk layanan eksternal
├── utils/          # Kode pendukung yang bisa digunakan di mana saja
└── README.md       # Dokumentasi ini
```

## Kategori File

### 📁 `core/` - Logika Bisnis Utama
Berisi file-file yang mengimplementasikan logika bisnis inti dari FrankLaraPloy:

- **`app-management.sh`** - Manajemen aplikasi Laravel (install, uninstall, configure)
- **`laravel-manager.sh`** - Fungsi-fungsi core Laravel (create, migrate, optimize, scheduler, queue)

### 📁 `modules/` - Driver/Plugin Layanan Eksternal
Berisi modul-modul yang berinteraksi dengan layanan dan teknologi eksternal:

- **`database-manager.sh`** - Driver untuk manajemen database MySQL
- **`octane-manager.sh`** - Plugin untuk Laravel Octane
- **`systemd-manager.sh`** - Driver untuk systemd services
- **`ssl-manager.sh`** - Plugin untuk manajemen SSL (FrankenPHP automatic)
- **`connection-manager.sh`** - Plugin untuk mengatasi masalah koneksi FrankenPHP

### 📁 `utils/` - Kode Pendukung
Berisi utility functions dan helper yang dapat digunakan di seluruh aplikasi:

- **`shared-functions.sh`** - Fungsi-fungsi bersama (logging, constants, helpers)
- **`error-handler.sh`** - Penanganan error dan rollback
- **`validation.sh`** - Modul validasi yang komprehensif
- **`security.sh`** - Konfigurasi dan fungsi security
- **`debug-manager.sh`** - Tools untuk debugging dan testing
- **`system-setup.sh`** - Setup system dan dependencies

## Keuntungan Struktur Baru

### 🎯 **Pemisahan yang Tegas**
- **Core**: Fokus pada logika bisnis Laravel/FrankenPHP
- **Modules**: Driver untuk teknologi eksternal yang dapat di-swap
- **Utils**: Helper functions yang reusable

### 🔧 **Maintainability**
- Lebih mudah untuk menemukan file yang relevan
- Isolasi concern yang jelas
- Dependency management yang lebih baik

### 📈 **Scalability**
- Mudah menambah modul baru
- Pattern yang konsisten untuk pengembangan
- Struktur yang familiar untuk developer

### 🔍 **Debugging**
- Error lebih mudah dilacak ke kategori yang tepat
- Testing dapat difokuskan per kategori
- Monitoring dapat diorganisir berdasarkan layer

## Dependency Graph

```
install.sh
├── utils/shared-functions.sh
├── utils/error-handler.sh
├── utils/validation.sh
├── utils/system-setup.sh
├── utils/security.sh
├── utils/debug-manager.sh
├── core/app-management.sh
├── core/laravel-manager.sh
└── modules/
    ├── octane-manager.sh
    ├── systemd-manager.sh
    ├── ssl-manager.sh
    ├── database-manager.sh
    └── connection-manager.sh
```

## Aturan Dependency

1. **Utils** tidak boleh depend pada **Core** atau **Modules**
2. **Core** boleh depend pada **Utils** dan **Modules** yang diperlukan
3. **Modules** boleh depend pada **Utils** saja
4. File dalam kategori yang sama sebaiknya tidak saling depend

## Cara Penggunaan

Struktur baru ini tetap kompatibel dengan cara penggunaan sebelumnya. Semua path reference telah diperbarui secara otomatis.

### Contoh Import:
```bash
# Utils
source "$SCRIPT_DIR/lib/utils/shared-functions.sh"
source "$SCRIPT_DIR/lib/utils/error-handler.sh"

# Core
source "$SCRIPT_DIR/lib/core/app-management.sh"

# Modules
source "$SCRIPT_DIR/lib/modules/octane-manager.sh"
```

---

📝 **Catatan**: Struktur ini mengikuti best practices untuk arsitektur clean code dan separation of concerns.
