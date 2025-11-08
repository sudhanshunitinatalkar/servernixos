{ config, pkgs, lib, ... }:

let
  # --- REMEMBER TO KEEP YOUR HASH UPDATED IF YOU CHANGE THE FILE ---
  tbRelease = pkgs.fetchurl {
    url = "https://github.com/sudhanshunitinatalkar/thingsboard/releases/download/v4.2/PBR_Research_Thingsboard.v4.tar.gz";
    sha256 = "sha256-V2q4dCDhKXO5jK4sotE9PVDCyGZmzgCu1dLWBwm3ALk="; 
  };

  tbHome = pkgs.runCommand "thingsboard-home" { } ''
    mkdir -p $out
    ${pkgs.gnutar}/bin/tar -xzf ${tbRelease} --strip-components=1 -C $out
  '';
  
  thingsboardJar = "${tbHome}/thingsboard-4.2.1-boot.jar";
  dbPassword = "thingsboard"; 

  envVars = {
    DATABASE_TS_TYPE = "sql";
    SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:5432/thingsboard?sslmode=disable";
    SPRING_DATASOURCE_USERNAME = "thingsboard";
    SPRING_DATASOURCE_PASSWORD = dbPassword;
    SQL_POSTGRES_TS_KV_PARTITIONING = "MONTHS";
  };
  
  setupPath = with pkgs; [ openjdk17 postgresql bash coreutils gnugrep util-linux ];
  
  setupScript = pkgs.writeShellScript "thingsboard-setup.sh" ''
    set -e
    export DATABASE_TS_TYPE="${envVars.DATABASE_TS_TYPE}"
    export SPRING_DATASOURCE_URL="${envVars.SPRING_DATASOURCE_URL}"
    export SPRING_DATASOURCE_USERNAME="${envVars.SPRING_DATASOURCE_USERNAME}"
    export SPRING_DATASOURCE_PASSWORD="${envVars.SPRING_DATASOURCE_PASSWORD}"
    export SQL_POSTGRES_TS_KV_PARTITIONING="${envVars.SQL_POSTGRES_TS_KV_PARTITIONING}"
    
    dataDir="/var/lib/thingsboard/data"
    
    run_as_pg() {
      ${pkgs.util-linux}/bin/runuser -u postgres -g postgres -- "$@"
    }

    echo "Starting ThingsBoard setup..."

    if [ ! -d "$dataDir/sql" ]; then
       echo "Populating $dataDir from release..."
       mkdir -p "$dataDir"
       cp -r ${tbHome}/data/* "$dataDir/"
       chown -R thingsboard:thingsboard "$dataDir"
       chmod -R u+rw "$dataDir"
    fi

    echo "Ensuring 'thingsboard' database user exists..."
    run_as_pg ${pkgs.postgresql}/bin/psql -c "
      DO \$\$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'thingsboard') THEN
          CREATE ROLE thingsboard LOGIN PASSWORD '${dbPassword}';
        ELSE
          ALTER ROLE thingsboard WITH LOGIN PASSWORD '${dbPassword}';
        END IF;
      END
      \$\$;"

    if ! run_as_pg ${pkgs.postgresql}/bin/psql -tAc "SELECT 1 FROM pg_database WHERE datname='thingsboard'" | grep -q 1; then
        echo "Creating database 'thingsboard'..."
        run_as_pg ${pkgs.postgresql}/bin/createdb thingsboard --owner=thingsboard
    fi

    if run_as_pg ${pkgs.postgresql}/bin/psql -d thingsboard -tAc "SELECT to_regclass('public.tb_user');" | grep -q "tb_user"; then
       echo "Database schema appears to be installed. Setup complete."
       exit 0
    fi
    
    echo "Schema missing. Running ThingsBoard installation..."
    # We also set HOME here for the installer just in case
    ${pkgs.util-linux}/bin/runuser -u thingsboard -g thingsboard -- \
      env HOME=/var/lib/thingsboard \
      ${pkgs.openjdk17}/bin/java \
        -cp ${thingsboardJar} \
        -Dloader.main=org.thingsboard.server.ThingsboardInstallApplication \
        -Dinstall.data_dir=$dataDir \
        -Dinstall.load_demo=true \
        org.springframework.boot.loader.launch.PropertiesLauncher
    
    echo "Installation finished successfully!"
  '';

in
{
  users.groups.thingsboard = {};
  users.users.thingsboard = {
    isSystemUser = true;
    group = "thingsboard";
    description = "ThingsBoard System User";
    home = "/var/lib/thingsboard"; # Explicitly set home directory
  };

  systemd.services.thingsboard-setup = {
    description = "ThingsBoard Database Setup";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    path = setupPath;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash ${setupScript}";
    };
  };

  systemd.services.thingsboard = {
    description = "ThingsBoard IoT Platform Server";
    after = [ "thingsboard-setup.service" "network.target" ];
    requires = [ "thingsboard-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ openjdk17 postgresql bash coreutils ];
    serviceConfig = {
      User = "thingsboard";
      Group = "thingsboard";
      Type = "simple";
      StateDirectory = "thingsboard";
      WorkingDirectory = "/var/lib/thingsboard"; # Set working directory
      Restart = "always";
      RestartSec = "10";
      # Explicitly set HOME so Java knows where to write .rocksdb and other temp files
      Environment = lib.mapAttrsToList (name: value: "${name}=${value}") envVars ++ [ "HOME=/var/lib/thingsboard" ];
      LoadCredential = [ "db_pass:/etc/nixos/secrets/tb_db_pass" ];
      ExecStart = ''
        ${pkgs.openjdk17}/bin/java \
          -Xms2G -Xmx2G \
          -Dinstall.data_dir=/var/lib/thingsboard/data \
          -jar ${thingsboardJar}
      '';
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/thingsboard 0750 thingsboard thingsboard -"
    "d /var/lib/thingsboard/data 0750 thingsboard thingsboard -"
  ];
}