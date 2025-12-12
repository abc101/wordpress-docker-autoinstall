# WordPress Docker Autoinstaller Template

This project uses Docker Compose to build a multi-container WordPress environment, including Nginx, PHP, MariaDB, and Redis.

It features the `init-wordpress.sh` shell script to automate the initial WordPress setup and inject HTTPS reverse-proxy configurations. It is designed to be compatible with both RHEL-based (SELinux) and Debian-based operating systems.

## 🚀 Key Features

  * **Simple Initialization:** Just run `docker compose up -d --build` followed by `sudo ./init-wordpress.sh`.
  * **Reverse-Proxy Ready:** Designed to work behind a main Host Nginx, automatically injecting HTTPS settings into `wp-config.php`.
  * **OS Compatibility:** Auto-detects RHEL/Rocky (SELinux) or Debian/Ubuntu and applies necessary security policies (`setsebool`).
  * **Resource Isolation:** Includes `deploy.resources.limits` in `docker-compose.yml` to prevent one site's traffic spike from impacting others (DDOS mitigation).
  * **Redis:** Install `Redis Object Cache` Wordpress plugin to connect Redis server.

## 📦 Project Structure

```
/srv/wordpress/your-site-name/
├── docker-compose.yml   # Defines all services (Nginx, PHP, DB, Redis)
├── Dockerfile           # Builds PHP with extensions (curl, gd, imagick, etc.)
├── init-wordpress.sh    # (CORE) The auto-installer script
├── sample.env                 # (IMPORTANT) DB passwords & sensitive info
├── nginx/
│   ├── nginx.conf       # Container's Nginx config (fastci_cache)
│   └── default.conf     # Container's Nginx config (connects to PHP-FPM)
│  
└── php/
    └── uploads.ini      # PHP settings like upload_max_filesize
```

## ⚙️ Prerequisites

1.  **Docker & Docker Compose:** Must be installed on the host VM.
2.  **Host Nginx:** A primary Nginx installed directly on the VM, handling ports 80/443.
3.  **Permissions:**
      * Your user account must be in the `docker` group.
      * This project folder (e.g., `/srv/wordpress/`) should be owned by a shared group like `wordpress-admins`.
        ```bash
        sudo groupadd wordpress-admins
        sudo mkdir -p /srv/wordpress
        sudo chmod 2775 /srv/wordpress
        sudo chgrp -R wordpress-admins /srv/wordpress
        sudo usermod -aG docker <your account>
        sudo usermod -aG wordpress-admins <your-account>
        ```

-----

## 📖 Installation Guide

This template is designed to run multiple WordPress sites on one server. **Repeat steps 1-7 for each new site you want to create.**

### Step 1: Copy Project Template

Create a folder for your new site (e.g., `your-site`) and copy all the template files into it.

```bash
# Example: Navigate to your main wordpress directory
cd /srv/wordpress/

# Copy the template files into a new site folder
cp -r /path/to/template/ ./<your-site>

# Move into the new site's directory
cd ./<your-site>
```

### Step 2: Configure `.env` File

Copy `sample.env` to `.env` and edit the `.env` file to set your database root and user passwords.  The `nginx` service's `ports`. This port **must be unique** for each site. **(Required)** 

```bash
cp sample.env .env
vi .env
```

```ini
# .env file: Environment variables for abc101.net site

# --- MariaDB Database Credentials ---
# (Replace placeholders with your actual strong passwords)
DB_DATABASE="your_db" 
DB_USER="your_user" 
DB_ROOT_PASSWORD="your_strong_user_password!"
DB_USER_PASSWORD="your_strong_user_password!"

# --- Host Port Configuration ---
HOST_PORT=<your_host_port>
```

### Step 3: Set Port in `docker-compose.yml` (Critical)

Adjust the `docker-compose.yml` file based on your server's needs, or use the default configuration.


### Step 4: Configure Host Nginx (Reverse Proxy)

Now, configure your **VM's main Nginx** (e.g., in `/etc/nginx/sites-available/` or `/etc/nginx/conf.d`) to act as a reverse proxy for the new container.

Create a new config file (e.g., `/etc/nginx/sites-available/<your.domain>.conf` or )`/etc/nginx/conf.d/<your.domain>.conf`:

```nginx
server {
    listen 80;
    server_name <your.domain>;

    # For certification
    root /var/www/<your_domain_directory> 

    location / {
        # Pass traffic to the localhost port you set in Step 3
        proxy_pass http://127.0.0.1:<your_host_port>; 
        
        # (Required) Pass visitor's real IP and protocol
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # You would also add your SSL (listen 443) settings here
    # and point them to the same proxy_pass directive.
}
```

Enable this site and restart the Host Nginx:

```bash
sudo ln -s /etc/nginx/sites-available/abc-shop.conf /etc/nginx/sites-enabled/
```
or / and just
```bash
sudo nginx -t
sudo systemctl restart nginx
```

### Step 5: Build and Start Containers

Now you are ready to build and start the Docker containers.

```bash
docker compose up -d --build
```

  * `--build`: This is only needed the first time (or if you change the `Dockerfile`).

### Step 6: Run the Initialization Script (One-Time) and complete WordPress Setup

This is the key step. Run the `init-wordpress.sh` script **with sudo**. It will detect the OS, set SELinux (if needed), download WordPress into the volume, and set permissions.

```bash
sudo chmod +x init-wordpress.sh
sudo ./init-wordpress.sh
```

When you see below message, 
```
🚀  Open your site in the browser to continue WordPress setup.
⏳  Wait for finishing WordPress initialization ...
```

1.  Open your domain (`http://your.domain`, `https://your.domain`) in a web browser.
2.  You will see the WordPress "Language Selection" screen without any stylesheet if you use `https`. It's Ok. Complete the default WordPress setup then WordPress setup will create `wp-config.php` file.
3.  The script (`init-wordpress.sh`) will automatically detect the new `wp-config.php` file and inject the HTTPS reverse-proxy settings. **(‼️ Important for HTTPS service)**

Your site is now live and fully configured.

-----

## 🛠️ Managing Your Site

  * **Start/Stop:**
      * `docker compose stop` (To temporarily stop the site, e.g., during a DDOS attack)
      * `docker compose start` (To restart it)
  * **Update/Rebuild:**
      * `docker compose build` (If you change the `Dockerfile`)
      * `docker compose up -d` (To apply any changes to `docker-compose.yml`)
  * **View Logs:**
      * `docker compose logs -f php` (To see live logs from the PHP container)
  * **Clean Up:**
      * `docker compose down` (Stops and *removes* containers and networks)
      * `docker compose down --volumes` (**DANGER:** Also deletes your database and WordPress files)
  * **Manage Volumes:**
      * `docker volume ls`
      * `docker volume inspect <your project's volume name>`
      * `sudo ls -l /var/lib/docker/volumes/wordpress_app_data/_data` (Example)