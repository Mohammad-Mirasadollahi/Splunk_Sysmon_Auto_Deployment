# Modular Sysmon Deployment Framework for Splunk

> **Note:** This project was developed with the assistance of Google Gemini.

This project provides a robust, two-part framework for deploying and managing Sysmon across a Windows environment using a Splunk Deployment Server. The architecture is designed for scalability, maintainability, and clear separation of concerns.

## Core Architecture

The framework is split into two distinct Splunk Technical Add-ons (TAs) to separate software management from configuration management. Both TAs should be deployed to the same clients and are triggered by inputs defined in their `inputs.conf` files.

### 1. `TA-Sysmon-Installer` (The Installer)
This TA is responsible for the Sysmon software installation lifecycle.
- **Manages the `sysmon.exe` binary itself.**
- **Installs the Sysmon service** for the first time using a minimal, process-only bootstrap config (`default/config.xml`) bundled with it.
- **Upgrades the Sysmon service** to a new version when you update the binary within the TA (the version is detected directly from `Sysmon.exe`).
- **Preserves the existing active configuration** in `C:\Windows\Sysmon\config.xml` during upgrades, so the authoritative config managed by `TA-Sysmon-Config` is never overwritten. The bundled config is applied only when no config exists yet (first install).
- **Handles uninstallation** and process cleanup via its `deploy.bat` script.
- This TA should be updated infrequently, only when a new version of Sysmon is released.

### 2. `TA-Sysmon-Config` (The Configurator)
This TA is responsible for the Sysmon configuration.
- **Forcefully overwrites the active Sysmon configuration** with its `config.xml` and applies it to the running service via `Sysmon -c`.
- **Periodically ensures** the running configuration on clients matches the one on the deployment server via its `update.bat` script.
- **Resolves `config.xml` the Splunk way:** `local/config.xml` (your customization) takes precedence over `default/config.xml` (a minimal, process-only config shipped with the app). Put your detailed, production-ready rules in `local/config.xml`. The file name is always `config.xml`, and no XML is kept under `bin/`.
- **Collects the Sysmon Operational event log** (`Microsoft-Windows-Sysmon/Operational`) into the `sysmon` index via a `WinEventLog` input.
- This TA will be updated frequently, every time you want to change a monitoring rule.

---

## Getting Started

Follow these steps to set up the framework.

**1. Place the Sysmon Executable and Default Config:**
- Download the latest version of Sysmon from [Sysinternals](https://docs.microsoft.com/en-us/sysinternals/downloads/sysmon).
- Place the `Sysmon.exe` file into the following directory:
  ```
  TA_Sysmon-Installer/bin/
  ```
- The bundled bootstrap config lives at `TA_Sysmon-Installer/default/config.xml` (a minimal, process-only config). To change the config applied at first install, add `TA_Sysmon-Installer/local/config.xml`, which overrides the default. Ongoing configuration is owned by `TA-Sysmon-Config`.

**2. Define Your Authoritative Sysmon Configuration:**
- Put your own Sysmon configuration (you can use [sysmon-modular](https://github.com/olafhartong/sysmon-modular)) at:
  ```
  TA_Sysmon-Config/local/config.xml
  ```
- This follows the standard Splunk `default`/`local` pattern: `local/config.xml` **overrides** the minimal `default/config.xml` that ships with the app. Do not edit `default/config.xml` — create `local/config.xml` instead. The file name is always `config.xml`, and no XML lives under `bin/`.

**3. Deploy to Splunk:**
- Copy both the `TA_Sysmon-Installer` and `TA_Sysmon-Config` folders to your Splunk Deployment Server's deployment-apps directory (e.g., `etc/deployment-apps`).
- From the Splunk UI or CLI, assign both TAs to your desired Windows server classes.

---

## How to Use

### To Upgrade the Sysmon Version:
1.  Replace the existing Sysmon.exe file with the new one in `TA_Sysmon-Installer/bin/`.
2.  On your Splunk Deployment Server, reload the deployment server (`./splunk reload deploy-server` or use the UI). The TA will be pushed, and the `deploy.bat` script will detect the new version directly from `Sysmon.exe` and handle the upgrade automatically.

### To Update the Sysmon Configuration:
1.  Edit your configuration at `TA_Sysmon-Config/local/config.xml` (this overrides the minimal `default/config.xml`).
2.  Reload the deployment server. The `TA-Sysmon-Config` app will be pushed to clients, and the `update.bat` script will copy `local/config.xml` (falling back to `default/config.xml`) and apply it via `Sysmon -c`.

---

## Logging & Troubleshooting

All deployment actions are logged on the client machines inside the `C:\Windows\Sysmon` folder. Each TA's `inputs.conf` runs its script as a scripted input and monitors the matching log file, forwarding the data to the `sysmon` index in Splunk by default:

- `TA-Sysmon-Installer` runs `deploy.bat` once per forwarder startup (`interval = -1`).
- `TA-Sysmon-Config` runs `update.bat` on a schedule (`interval = 3600`, i.e. hourly) and collects the Sysmon Operational event log via a `WinEventLog` input.

- **Installer/Upgrade Logs:** `C:\Windows\Sysmon\sysmon_installer.log`
  - Generated by `TA_Sysmon-Installer`.
- **Configuration Update Logs:** `C:\Windows\Sysmon\sysmon_config_updater.log`
  - Generated by `TA_Sysmon-Config`.

> **Note:** `TA-Sysmon-Config` collects the Sysmon Operational event log (`Microsoft-Windows-Sysmon/Operational`) into the `sysmon` index via its `WinEventLog` input. For CIM-compliant field extraction of those events, also install the official [Splunk Add-on for Microsoft Sysmon](https://splunkbase.splunk.com/app/5709) on your search heads and indexers.
