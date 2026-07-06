{ lib, pkgs, ... }:
let
  toshySessionVariables = pkgs.toshy.passthru.sessionVariables;
  toshyPrograms = pkgs.toshy.passthru.checkedPrograms;
in
{
  name = "toshy";

  meta.maintainers = with lib.maintainers; [ _4evy ];

  nodes.machine =
    { config, pkgs, ... }:
    {
      assertions = [
        {
          assertion = lib.all (
            variable: lib.elem variable config.services.xserver.displayManager.importedVariables
          ) toshySessionVariables;
          message = "Toshy session variables must be imported into the systemd user environment.";
        }
      ];

      services.toshy = {
        enable = true;
        hidAppleFnmode = 2;
        users = [ "alice" ];
      };

      users.users.alice = {
        isNormalUser = true;
        uid = 1000;
      };

      users.users.bob = {
        isNormalUser = true;
        uid = 1001;
      };
    };

  testScript = ''
    machine.wait_for_unit("systemd-tmpfiles-setup.service")

    machine.succeed("test -d ~alice/.config/toshy")
    machine.succeed("test -f ~alice/.config/toshy/toshy_config.py")
    machine.succeed("test $(stat -c %a ~alice/.config/toshy) = 700")
    machine.succeed("test $(stat -c %a ~alice/.config/toshy/toshy_config.py) = 600")
    machine.fail("test -e ~bob/.config/toshy/toshy_config.py")

    machine.succeed("loginctl enable-linger alice bob")
    machine.wait_until_succeeds("systemctl --user --machine=alice@ is-active systemd-tmpfiles-setup.service")
    machine.wait_until_succeeds("systemctl --user --machine=bob@ is-active systemd-tmpfiles-setup.service")

    machine.succeed("id -nG alice | grep -qw input")
    machine.succeed("id -nG alice | grep -qw uinput")
    machine.fail("id -nG bob | grep -qw input")
    machine.fail("id -nG bob | grep -qw uinput")
    machine.wait_for_file("/dev/uinput")
    machine.succeed("grep -qxF 'options hid_apple fnmode=2' /etc/modprobe.d/nixos.conf")
    machine.succeed("grep -qxF '[XWayKeyz Virtual Keyboard]' /etc/libinput/local-overrides.quirks")
    machine.succeed("grep -qxF 'AttrKeyboardIntegration=internal' /etc/libinput/local-overrides.quirks")

    for program in ${builtins.toJSON toshyPrograms}:
        machine.succeed(f"test -x /run/current-system/sw/bin/{program}")

    for unit in (
        "toshy-config",
        "toshy-cosmic-dbus",
        "toshy-kwin-dbus",
        "toshy-session-monitor",
        "toshy-tray",
        "toshy-wlroots-dbus",
    ):
        machine.succeed(f"systemctl --user --machine=alice@ is-enabled {unit}.service")
        unit_text = machine.succeed(f"cat /etc/systemd/user/{unit}.service")
        t.assertIn("NoNewPrivileges=true", unit_text)
        t.assertIn("ExecCondition=", unit_text)
        t.assertIn("PrivateTmp=true", unit_text)
        t.assertIn("ProtectKernelTunables=true", unit_text)
        t.assertIn("RestrictAddressFamilies=AF_UNIX", unit_text)
        t.assertIn("SystemCallArchitectures=native", unit_text)
        t.assertNotIn("/run/current-system/sw/bin", unit_text)
        t.assertNotIn("/run/wrappers/bin", unit_text)
        t.assertIn('Environment="TERM=xterm"', unit_text)
        t.assertIn("SyslogIdentifier=", unit_text)
        t.assertIn("UMask=0077", unit_text)
        if unit in ("toshy-cosmic-dbus", "toshy-kwin-dbus", "toshy-wlroots-dbus"):
            t.assertIn("ExecStartPre=", unit_text)
            t.assertIn("Restart=on-failure", unit_text)
            t.assertIn("StartLimitBurst=5", unit_text)
            t.assertIn("StartLimitIntervalSec=60", unit_text)
            t.assertIn(${builtins.toJSON pkgs.runtimeShell}, unit_text)
            t.assertNotIn("bash-interactive", unit_text)
            t.assertIn("XDG_SESSION_TYPE", unit_text)
        elif unit in ("toshy-config", "toshy-session-monitor"):
            t.assertIn("Restart=always", unit_text)

    allowed_users_file = machine.succeed(
        "grep -ho '/nix/store/[^ ]*-toshy-users' /etc/systemd/user/toshy-config.service | head -n1"
    ).strip()
    machine.succeed(f"grep -qxF alice {allowed_users_file}")
    machine.fail(f"grep -qxF bob {allowed_users_file}")
  '';
}
