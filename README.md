# Modular Sysmon Deployment Framework for Splunk

> **Note:** This project was developed with the assistance of Google Gemini.

This project provides a robust, two-part framework for deploying and managing Sysmon across a Windows environment using a Splunk Deployment Server. The architecture is designed for scalability, maintainability, and clear separation of concerns.

## Core Architecture

The framework is split into two distinct Splunk Technical Add-ons (TAs) to separate software management from configuration management. Both TAs should be deployed to the same clients and are triggered by inputs defined in their `inputs.conf` files.

### 1. `TA-Sysmon-Binary` (The Installer)
This TA is responsible for the Sysmon software installation lifecycle.
- **Manages the `sysmon.exe` binary itself.**
- **Installs the Sysmon service** for the first time using the `config.xml` bundled with it as a default.
- **Upgrades the Sysmon service** to a new version when you update the binary within the TA.
- **Intelligently preserves existing user configurations** found in `C:\Windows\Sysmon\` during an upgrade.
- **Handles uninstallation** and process cleanup via its `deploy.bat` script.
- This TA should be updated infrequently, only when a new version of Sysmon is released.

### 2. `TA-Sysmon-Config` (The Configurator)
This TA is responsible for the Sysmon configuration.
- **Forcefully overwrites the active Sysmon configuration** with the `config.xml` bundled with it.
- **Periodically ensures** the running configuration on clients matches the one on the deployment server via its `update.bat` script.
- **Contains your detailed, production-ready `config.xml`** with all your custom rules.
- This TA will be updated frequently, every time you want to change a monitoring rule.

---

## Getting Started

Follow these steps to set up the framework.

**1. Place the Sysmon Executable and Default Config:**
- Download the latest version of Sysmon from [Sysinternals](https://docs.microsoft.com/en-us/sysinternals/downloads/sysmon).
- Place the `Sysmon.exe` file into the following directory:
  ```
  TA_Sysmon-Binary/bin/
  ```

**2. Define Your Authoritative Sysmon Configuration:**
- Customize the following file with your own sysmon configuration. You can also use [sysmon-modular](https://github.com/olafhartong/sysmon-modular):
  ```
  TA_Sysmon-Config/bin/config.xml
  ```
- This is your primary, authoritative configuration file. Customize it with all the rules and event filters you need for your environment.

**3. Deploy to Splunk:**
- Copy both the `TA_Sysmon-Binary` and `TA_Sysmon-Config` folders to your Splunk Deployment Server's deployment-apps directory (e.g., `etc/deployment-apps`).
- From the Splunk UI or CLI, assign both TAs to your desired Windows server classes.

---

## How to Use

### To Upgrade the Sysmon Version:
1.  Replace the existing Sysmon.exe file with the new one in `TA_Sysmon-Binary/bin/`.
2.  Open the `sysmon_version.conf` file and update the version to match the new Sysmon version.
3.  On your Splunk Deployment Server, reload the deployment server (`./splunk reload deploy-server` or use the UI). The TA will be pushed, and the `deploy.bat` script will handle the upgrade.

### To Update the Sysmon Configuration:
1.  Edit your main configuration file: `TA_Sysmon-Config/bin/config.xml`.
2.  Reload the deployment server. The `TA-Sysmon-Config` app will be pushed to clients, and the `update.bat` script will apply the new configuration.

---

## Logging & Troubleshooting

All deployment actions are logged on the client machines inside a dedicated Sysmon folder. The `inputs.conf` within each TA is configured to monitor these logs and the Sysmon Windows Event Log, forwarding all data to the `sysmon` index in Splunk by default.

- **Installer/Upgrade Logs:** `C:\Windows\Sysmon\sysmon_installer.log`
  - Generated by `TA_Sysmon-Binary`.
- **Configuration Update Logs:** `C:\Windows\Sysmon\sysmon_config_updater.log`
  - Generated by `TA_Sysmon-Config`.
