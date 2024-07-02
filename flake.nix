{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  outputs = { self, nixpkgs }: {
    nixosModules.latex_templater = { config, lib, pkgs, ... }:
      let
        uwsgi = pkgs.uwsgi.override { plugins = [ "python3" ]; };
        latex_templater = ./latex_templater;
        pyhonEnv = pkgs.python3.withPackages (ps: with ps; [ flask ]);
        texlive = pkgs.texlive.combine {
          inherit (pkgs.texlive) scheme-basic
            anyfontsize pgf babel-hungarian hyphenat;
        };
        cfg = config.services.latex_templater;
      in
      {
        options.services.latex_templater = {
          enable = lib.mkEnableOption "the latex_templater service";
          hostName = lib.mkOption {
            type = lib.types.str;
            description = lib.mdDoc "The nginx virtual host.";
          };
          urlPrefix = lib.mkOption {
            type = lib.types.str;
            default = "/latex_templater";
            description = lib.mdDoc "The URL prefix under which the main page appears.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 5000;
            description = lib.mdDoc "The local port the service binds to.";
          };
        };
        config = lib.mkIf cfg.enable {
          users = {
            # Cannot use DynamicUser: https://github.com/NixOS/nixpkgs/pull/289593
            users.latex_templater = {
              group = "latex_templater";
              isSystemUser = true;
            };
            groups.latex_templater = { };
          };

          systemd.services.latex_templater = {
            description = "Latex templater";
            path = [ texlive ];
            serviceConfig = {
              ExecStart = lib.strings.escapeShellArgs [
                "${uwsgi}/bin/uwsgi"
                "--http-socket"
                "127.0.0.1:${toString cfg.port}"
                "--plugins"
                "python3"
                "--pyhome"
                "${pyhonEnv}"
                "--wsgi-file"
                "${latex_templater}/main.py"
              ];
              Restart = "on-failure";

              # Paths
              WorkingDirectory = "${latex_templater}";
              ProtectProc = "invisible";
              ProcSubset = "pid";

              # User/Group Identity
              User = config.users.users."latex_templater".name;
              Group = config.users.groups."latex_templater".name;

              # Capabilities
              CapabilityBoundingSet = "";
              AmbientCapabilities = "";

              # Security
              NoNewPrivileges = true;

              # Process Properties
              UMask = "0066";

              # Sandboxing
              ProtectHome = "tmpfs";
              PrivateIPC = true;
              ProtectHostname = true;
              ProtectClock = true;
              ProtectKernelLogs = true;
              RestrictAddressFamilies = [ "AF_INET" ];
              RestrictNamespaces = true;
              LockPersonality = true;
              MemoryDenyWriteExecute = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              RemoveIPC = true;

              # System Call Filtering
              SystemCallFilter = [
                # Numbers are for x86-64
                "read" # 0
                "write" # 1
                "close" # 3
                "fstat" # 5
                "lseek" # 8
                "rt_sigaction" # 13
                "rt_sigprocmask" # 14
                "ioctl" # 16
                "pread64" # 17
                "writev" # 20
                "access" # 21
                "dup2" # 33
                "getpid" # 39
                "sendfile" # 40
                "socket" # 41
                "connect" # 42
                "bind" # 49
                "listen" # 50
                "getsockname" # 51
                "setsockopt" # 54
                "vfork" # 58
                "wait4" # 61
                "kill" # 62
                "uname" # 63
                "fcntl" # 72
                "getcwd" # 79
                "rename" # 82
                "mkdir" # 83
                "rmdir" # 84
                "unlink" # 87
                "readlink" # 89
                "sysinfo" # 99
                "prctl" # 157
                "epoll_create" # 213
                "getdents64" # 217
                "restart_syscall" # 219
                "timer_settime" # 223
                "clock_gettime" # 228
                "epoll_wait" # 232
                "epoll_ctl" # 233
                "openat" # 257
                "newfstatat" # 262
                "unlinkat" # 263
                "accept4" # 288
                "epoll_create1" # 291
                "pipe2" # 293
                "close_range" # 436
              ];
              SystemCallArchitectures = "native";

              # CPU Accounting and Control
              CPUWeight = 50;
              CPUQuota = "100%";

              # Memory Accounting and Control
              # Measured max was 92MiB in practice
              MemoryHigh = "128M";
              MemoryMax = "200M";

              # Process Accounting and Control
              TasksMax = 8;

              # Network Accounting and Control
              IPAddressDeny = "any";
              IPAddressAllow = "localhost";
              SocketBindDeny = "any";
              SocketBindAllow = "ipv4:tcp:${toString cfg.port}";
              RestrictNetworkInterfaces = "lo";

              # Device Access
              DeviceAllow = "";
            };
            confinement = {
              # This runs the service with a tmpfs based root filesystem, with
              # only the needed store paths bind-mounted.
              enable = true;
              packages = [
                # This needs to be added to the closure, otherwise python defaults to non-UTF8.
                config.systemd.globalEnvironment.LOCALE_ARCHIVE
                texlive
              ];
            };
            wantedBy = [ "multi-user.target" ];
          };

          services.nginx = {
            enable = lib.mkDefault true;
            virtualHosts.${cfg.hostName} = {
              locations."${cfg.urlPrefix}/".proxyPass = "http://127.0.0.1:${toString cfg.port}/";
            };
          };
        };
      };

    # VM for testing/development. You can start it like this:
    # `$(nix build --print-out-paths .#nixosConfigurations.test-vm.config.system.build.vm)/bin/run-nixos-vm`
    nixosConfigurations.test-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.latex_templater
        ({ config, pkgs, modulesPath, ... }: {
          imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
          system.stateVersion = "24.05";
          virtualisation = {
            graphics = false;
            forwardPorts = [{ from = "host"; host.port = 5000; guest.port = 80; }];
          };
          services.getty.autologinUser = "user";
          users.extraUsers.user = {
            password = "";
            group = "wheel";
            isNormalUser = true;
          };
          security.sudo = {
            enable = true;
            wheelNeedsPassword = false;
          };
          programs.bash.loginShellInit = ''trap "sudo poweroff" EXIT'';
          services.latex_templater = {
            enable = true;
            hostName = "localhost";
          };
          networking.firewall.allowedTCPPorts = [ 80 ];
        })
      ];
    };
  };
}
