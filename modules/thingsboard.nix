# pbrserver/hosts/thingsboard.nix
{ config, lib, pkgs, ... }:

with lib; # This gives us helpful functions like "mkIf"

let
  # This is where we will define the service options
  cfg = config.services.thingsboard;

  # 1. FETCH THE JAR
  # This downloads your JAR. We use a placeholder SHA256.
  thingsboardJar = pkgs.fetchurl 
  {
    url = "https://github.com/sudhanshunitinatalkar/thingsboard/releases/download/v4.2/thingsboard-4.2.1-boot.jar";
    sha256 = "5qzyiRlZ7xco0h0zh8+mE03W4ak1pKcg5OIzlyQDz3c"; # <-- REPLACE THIS after first build
  };

in
{
  # --- 1. DEFINE NEW OPTIONS ---
  # This makes "services.thingsboard.enable" a real option
  # you can use in your configuration.nix
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
  # This block of code will only be activated
  # if you set "services.thingsboard.enable = true;"
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

    # --- Configure the Database (Step 1 from nix.md) ---
    # This MERGES with your existing postgresql config.
    # It adds the user and database for you.
    services.postgresql = 
    {
      # We don't need 'enable' or 'package' here,
      # because your configuration.nix  already has it!
      ensureUsers = 
      [{
        name = "thingsboard";
        passwordFile = cfg.dbPasswordFile;
      }];
      ensureDatabases = 
      [{
        name = "thingsboard";
        owner = "thingsboard";
      }];
    };

    # --- Create the systemd services ---
    systemd.services = 
    {

      # This is "Step 2" from nix.md: Install the Schema
      thingsboard-schema = 
      {
        description = "ThingsBoard Schema Installation";
        # This service must run after Postgres is ready
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];

        serviceConfig = 
        {
          Type = "oneshot"; # It runs once and exits
          RemainAfterExit = true;
          User = "thingsboard"; # Run as the 'thingsboard' user
          Environment = "PATH=${pkgs.postgresql}/bin:$PATH"; # So it can find 'psql'
        };

        # This script checks if the DB is installed. If not, it runs the installer.
        # This makes the service safe to run on every boot.
        preStart = ''
          # Wait for the database to be ready
          until psql -U thingsboard -d thingsboard -c "select 1" >/dev/null 2>&1; do
            echo "Waiting for PostgreSQL..."
            sleep 1
          done

          # Check if the 'device' table exists. If it does, we're done.
          if psql -U thingsboard -d thingsboard -c '\dt device' | grep -q 'device'; then
            echo "ThingsBoard schema already exists. Skipping installation."
          else
            echo "Running ThingsBoard schema installation..."
            mkdir -p /var/lib/thingsboard/data
            # This is the installer command from your nix.md
            ${pkgs.openjdk17}/bin/java \
              -cp ${thingsboardJar} \
              -Dloader.main=org.thingsboard.server.ThingsboardInstallApplication \
              -Dinstall.data_dir=/var/lib/thingsboard/data \
              -Dinstall.load_demo=true \
              org.springframework.boot.loader.launch.PropertiesLauncher
          fi
        '';

        # Environment variables from your nix.md
        environment = 
        {
          DATABASE_TS_TYPE = "sql";
          SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:5432/thingsboard";
          SPRING_DATASOURCE_USERNAME = "thingsboard";
          SPRING_DATASOURCE_PASSWORD_FILE = cfg.dbPasswordFile;
          SQL_POSTGRES_TS_KV_PARTITIONING = "MONTHS";
        };
      };

      # This is "Step 3" from nix.md: Run the Server
      thingsboard = {
        description = "ThingsBoard IoT Platform Server";
        wantedBy = [ "multi-user.target" ]; # Start on boot
        
        # It must wait for the schema installation to be "done"
        after = [ "thingsboard-schema.service" ];
        requires = [ "thingsboard-schema.service" ];

        serviceConfig = 
        {
          # This is the main server command from your nix.md
          ExecStart = ''
            ${pkgs.openjdk17}/bin/java -Xms2G -Xmx2G -jar ${thingsboardJar}
          '';
          User = "thingsboard";
          WorkingDirectory = "/var/lib/thingsboard";
          Restart = "on-failure"; # Automatically restart if it crashes
          RestartSec = "10s";
        };

        # The same environment variables for the main server
        environment = {
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