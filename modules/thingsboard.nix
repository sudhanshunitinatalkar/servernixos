# pbrserver/hosts/thingsboard.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.thingsboard;

  thingsboardJar = pkgs.fetchurl 
  {
    url = "https://github.com/sudhanshunitinatalkar/thingsboard/releases/download/v4.2/thingsboard-4.2.1-boot.jar";
    # This is the correct, full hash from your previous error
    sha256 = "sha256-5qzyiRlZ7xco0h0zh8+mE03W4ak1pKcg5OIzlyQDz3c=";
  };

in
{
  # --- 1. DEFINE NEW OPTIONS ---
  options.services.thingsboard = 
  {
    enable = mkEnableOption "ThingsBoard IoT Platform";

    dbPasswordFile = mkOption 
    {
      type = types.path;
      description = "Path to a file containing *only* the password for the thingsboard database user.";
      example = "/etc/nixos/secrets/thingsboard.pass";
    };
  };

  # --- 2. CONFIGURE THE SYSTEM ---
  config = mkIf cfg.enable 
  {

    # --- Create a system user for the service ---
    users.users.thingsboard = 
    {
      isSystemUser = true;
      group = "thingsboard";
      home = "/var/lib/thingsboard";
    };
    users.groups.thingsboard = {};

    # --- Create the systemd services ---
    systemd.services = {

      # This is "Step 2" from nix.md: Install the Schema
      thingsboard-schema = 
      {
        description = "ThingsBoard Schema Installation";
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];

        # We use 'root' to set up the database,
        # then 'sudo' to run the installer as the 'thingsboard' user.
        serviceConfig = 
        {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root"; # <-- CHANGED
          # This gives us 'psql' and 'sudo'
          Environment = "PATH=${pkgs.postgresql}/bin:${pkgs.sudo}/bin:${pkgs.coreutils}/bin:$PATH";
        };

        # This script now contains all the logic from your nix.md
        script = 
        ''
          set -e  # Exit immediately if a command exits with a non-zero status.
          set -x  # Print commands and their arguments as they are executed.

          # Wait for the database to be ready (run as postgres user)
          until sudo -u postgres psql -c "select 1" >/dev/null 2>&1;
          do
            echo "Waiting for PostgreSQL..."
            sleep 1
          done

          # Read the password from the secret file
          DB_PASSWORD=$(cat ${cfg.dbPasswordFile})

          echo "Ensuring database user 'thingsboard' exists..."
          # Create user if it doesn't exist (run as postgres user)
          sudo -u postgres psql -c "CREATE USER thingsboard" 2>/dev/null || echo "User already exists."

          echo "Setting 'thingsboard' user password..."
          # Set the password using "dollar-quoting" to handle any special characters
          sudo -u postgres psql -c "ALTER USER thingsboard WITH PASSWORD $password$$DB_PASSWORD$password$;"

          echo "Ensuring database 'thingsboard' exists..."
          # Create DB if it doesn't exist (run as postgres user)
          sudo -u postgres psql -c "CREATE DATABASE thingsboard OWNER thingsboard" 2>/dev/null || echo "Database already exists."

          echo "Granting privileges..."
          # Grant privileges to the user for the database
          sudo -u postgres psql -d thingsboard -c "GRANT ALL PRIVILEGES ON DATABASE thingsboard TO thingsboard;"

          # Check if the 'device' table exists (run as postgres user)
          if sudo -u postgres psql -d thingsboard -c '\dt device' 2>/dev/null | grep -q 'device'; then
            echo "ThingsBoard schema already exists. Skipping installation."
          else
            echo "Running ThingsBoard schema installation..."
            mkdir -p /var/lib/thingsboard/data
            chown thingsboard:thingsboard /var/lib/thingsboard/data

            # Run the installer as the 'thingsboard' user
            # This will now connect using the password we set
            sudo -u thingsboard \
              ${pkgs.openjdk17}/bin/java \
                -cp ${thingsboardJar} \
                -Dloader.main=org.thingsboard.server.ThingsboardInstallApplication \
                -Dinstall.data_dir=/var/lib/thingsboard/data \
                -Dinstall.load_demo=true \
                org.springframework.boot.loader.launch.PropertiesLauncher
          fi
          echo "ThingsBoard schema script finished."
        '';

        # Environment variables for the Java installer
        environment = 
        {
          DATABASE_TS_TYPE = "sql";
          SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:5432/thingsboard";
          SPRING_DATASOURCE_USERNAME = "thingsboard";
          # The installer reads this and gets the password from the file
          SPRING_DATASOURCE_PASSWORD_FILE = cfg.dbPasswordFile;
          SQL_POSTGRES_TS_KV_PARTITIONING = "MONTHS";
        };
      };

      # This is "Step 3" from nix.md: Run the Server
      thingsboard = 
      {
        description = "ThingsBoard IoT Platform Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "thingsboard-schema.service" ];
        requires = [ "thingsboard-schema.service" ];

        serviceConfig = 
        {
          ExecStart = ''
            ${pkgs.openjdk17}/bin/java -Xms2G -Xmx2G -jar ${thingsboardJar}
          '';
          User = "thingsboard"; # <-- This service runs as the correct user
          WorkingDirectory = "/var/lib/thingsboard";
          Restart = "on-failure";
          RestartSec = "10s";
        };

        # Environment variables for the main server
        environment = 
        {
          DATABASE_TS_TYPE = "sql";
          SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:5432/thingsboard";
          SPRING_DATASOURCE_USERNAME = "thingsboard";
          SPRING_DATASOURCE_PASSWORD_FILE = cfg.dbPasswordFile;
          SQL_POSTGRES_TS_KV_PARTITIONING = "MONTHS";
        };
      };
    };
  };
}