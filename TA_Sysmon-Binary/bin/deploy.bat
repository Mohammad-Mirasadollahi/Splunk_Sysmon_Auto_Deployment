@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

REM --- ======================================================================
REM --- Configuration
REM --- Define all key variables and paths in this section.
REM --- ======================================================================

REM --- The official name of the Windows service for Sysmon.
SET "SERVICE_NAME=Sysmon"

REM --- The dedicated installation directory for all Sysmon components.
REM --- This centralizes the executable, config, and log files.
SET "TARGET_DIR=%WINDIR%\Sysmon"

REM --- The log file for this script's execution, located within the target directory.
SET "LOG_FILE=%TARGET_DIR%\sysmon_installer.log"

REM --- A temporary file used to capture the output of Sysmon version checks.
SET "TEMP_OUTPUT_FILE=%TEMP%\sysmon_version_check.tmp"

REM --- Paths to the files bundled with this script.
REM --- %~dp0 expands to the directory where this batch script is located.
SET "SCRIPT_DIR=%~dp0"
SET "LOCAL_SYSMON_EXE=%SCRIPT_DIR%Sysmon.exe"
SET "BUNDLED_CONFIG_FILE=%SCRIPT_DIR%config.xml"

REM --- Full paths to the components as they will exist on the target system.
SET "INSTALLED_SYSMON_EXE=%TARGET_DIR%\Sysmon.exe"
SET "FINAL_CONFIG_FILE=%TARGET_DIR%\config.xml"


REM --- ======================================================================
REM --- Script Execution Start
REM --- ======================================================================

REM --- Ensure the target directory exists before any logging can occur.
IF NOT EXIST "%TARGET_DIR%" MKDIR "%TARGET_DIR%"

CALL :log "INFO" "action='start_execution' script_name='deploy.bat'"

REM --- Critical check: The script cannot run without the Sysmon executable.
IF NOT EXIST "%LOCAL_SYSMON_EXE%" (
    CALL :log "ERROR" "action='check_local_file' status='fatal' message='Sysmon.exe not found next to the script.'"
    GOTO :EOF
)

REM --- [!!!] CORE LOGIC - STEP 1: Get the currently installed version BEFORE overwriting files.
REM --- This is critical to correctly compare the old version with the new one.
sc query "!SERVICE_NAME!" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    REM --- The service exists, so try to read its version from the existing executable.
    CALL :get_installed_version
)

REM --- [!!!] CORE LOGIC - STEP 2: Prepare the environment.
REM --- This copies the new executable and handles the config file logic.
CALL :prepare_environment
IF %ERRORLEVEL% NEQ 0 GOTO :cleanup

REM --- [!!!] CORE LOGIC - STEP 3: Get the version of the new target executable.
CALL :get_target_version
IF NOT DEFINED TARGET_SYSMON_VERSION (
    CALL :log "ERROR" "action='read_target_version' status='failed' message='Could not determine version from local Sysmon.exe.'"
    GOTO :cleanup
)

REM --- [!!!] CORE LOGIC - STEP 4: Main Decision Flow.
REM --- Compare versions and decide on the appropriate action.
IF NOT DEFINED INSTALLED_VERSION (
    REM --- The service was not found, so this is a first-time installation.
    CALL :log "INFO" "action='install_check' status='not_installed'. Proceeding with first-time installation."
    GOTO :first_time_install
)

IF "!INSTALLED_VERSION!"=="!TARGET_SYSMON_VERSION!" (
    REM --- Versions match, no action is needed besides ensuring the service is running.
    CALL :log "INFO" "action='version_compare' status='up_to_date'. No action needed."
    CALL :verify_service_status
    GOTO :cleanup
)

REM --- The installed version is different from the target version, so an upgrade is required.
CALL :log "INFO" "action='version_compare' status='outdated' installed='!INSTALLED_VERSION!' target='!TARGET_SYSMON_VERSION!'. Proceeding with upgrade."
GOTO :upgrade_service


REM --- ======================================================================
REM --- Action Blocks
REM --- These blocks define the high-level workflows.
REM --- ======================================================================

:first_time_install
    CALL :log "INFO" "action='first_time_install' status='starting'"
    CALL :install_service
    CALL :verify_service_status
    GOTO :cleanup

:upgrade_service
    CALL :log "INFO" "action='upgrade_service' status='starting'"
    CALL :uninstall_service
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "WARN" "action='upgrade_service' status='continue_after_uninstall_fail' message='Could not uninstall old version (maybe not running?). Proceeding...'"
    )
    CALL :force_kill_process
    CALL :install_service
    CALL :verify_service_status
    GOTO :cleanup

:cleanup
    REM --- Clean up temporary files and log the end of execution.
    IF EXIST "%TEMP_OUTPUT_FILE%" DEL "%TEMP_OUTPUT_FILE%"
    CALL :log "INFO" "action='end_execution' script_name='deploy.bat' status='finished'"
    GOTO :EOF


REM --- ======================================================================
REM --- Subroutines
REM --- These are the functional building blocks of the script.
REM --- ======================================================================

:prepare_environment
    CALL :log "INFO" "action='prepare_environment' status='starting'"
    
    REM --- Copy the new Sysmon executable from the script's directory to the target directory.
    COPY /Y "%LOCAL_SYSMON_EXE%" "%INSTALLED_SYSMON_EXE%" > NUL
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='copy_executable' status='failed' error_code='%ERRORLEVEL%'"
        EXIT /B 1
    )

    REM --- Handle the configuration file with a clear priority order.
    IF EXIST "%FINAL_CONFIG_FILE%" (
        REM --- Priority 1: A config file already exists in the target directory. Respect user's custom config.
        CALL :log "INFO" "action='config_check' status='found_existing' message='Using existing user config file.'"
    ) ELSE IF EXIST "%BUNDLED_CONFIG_FILE%" (
        REM --- Priority 2: No user config exists, so copy the bundled config file.
        CALL :log "INFO" "action='config_check' status='found_bundled' message='Copying bundled config file to target directory.'"
        COPY /Y "%BUNDLED_CONFIG_FILE%" "%FINAL_CONFIG_FILE%" > NUL
        IF %ERRORLEVEL% NEQ 0 (
            CALL :log "ERROR" "action='copy_config' status='failed' error_code='%ERRORLEVEL%'"
            EXIT /B 1
        )
    ) ELSE (
        REM --- Fatal Error: No config file available anywhere. The script cannot proceed.
        CALL :log "ERROR" "action='config_check' status='fatal' message='No config file found. Cannot proceed.'"
        EXIT /B 1
    )
    EXIT /B 0

:install_service
    CALL :log "INFO" "action='install_service' status='starting' config_path='%FINAL_CONFIG_FILE%'"
    
    REM --- Install the service using the new executable and the determined config file.
    REM --- -accepteula is crucial for non-interactive/automated execution.
    "%INSTALLED_SYSMON_EXE%" -accepteula -i "%FINAL_CONFIG_FILE%" > NUL
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='install_service' status='failed' error_code='%ERRORLEVEL%'"
    ) ELSE (
        CALL :log "INFO" "action='install_service' status='success'"
    )
    GOTO :EOF

:uninstall_service
    CALL :log "INFO" "action='uninstall_service' status='starting'"
    
    REM --- If the executable doesn't exist, we can assume it's not installed. Exit gracefully.
    IF NOT EXIST "%INSTALLED_SYSMON_EXE%" ( EXIT /B 0 )

    REM --- Use the '-u force' switch to ensure uninstallation proceeds even if the service state is inconsistent.
    "%INSTALLED_SYSMON_EXE%" -u force > NUL
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "WARN" "action='uninstall_service' status='failed_or_not_installed' error_code='%ERRORLEVEL%'"
        EXIT /B 1
    )
    CALL :log "INFO" "action='uninstall_service' status='success'"
    EXIT /B 0

:force_kill_process
    CALL :log "INFO" "action='force_kill_process' status='starting' process_name='sysmon.exe'"
    
    REM --- Forcefully terminate any lingering sysmon.exe process.
    REM --- /T also terminates any child processes.
    REM --- Redirect output to NUL to suppress errors if the process is not found.
    taskkill /F /IM sysmon.exe /T >nul 2>&1
    GOTO :EOF

:verify_service_status
    CALL :log "INFO" "action='verify_service_status' status='checking' service_name='!SERVICE_NAME!'"
    
    REM --- Check if the service is in the RUNNING state.
    sc query "!SERVICE_NAME!" | find "STATE" | find "RUNNING" >nul
    IF %ERRORLEVEL% NEQ 0 (
        REM --- If not running, attempt to start it.
        CALL :log "WARN" "action='verify_service_status' status='not_running' message='Attempting to start the service.'"
        net start "!SERVICE_NAME!" >nul
        IF %ERRORLEVEL% NEQ 0 (
            CALL :log "ERROR" "action='verify_service_status' status='start_failed' error_code='%ERRORLEVEL%'"
        ) ELSE (
            CALL :log "INFO" "action='verify_service_status' status='start_success'"
        )
    ) ELSE (
        CALL :log "INFO" "action='verify_service_status' status='already_running'"
    )
    GOTO :EOF

:get_target_version
    SET "TARGET_SYSMON_VERSION="
    REM --- Read version from the executable bundled with the script.
    "%LOCAL_SYSMON_EXE%" > "%TEMP_OUTPUT_FILE%" 2>&1
    IF NOT EXIST "%TEMP_OUTPUT_FILE%" ( GOTO :EOF )
    FOR /F "tokens=3" %%v IN ('findstr /B "System Monitor" "%TEMP_OUTPUT_FILE%"') DO ( SET "TARGET_SYSMON_VERSION=%%v" )
    IF DEFINED TARGET_SYSMON_VERSION ( 
        SET "TARGET_SYSMON_VERSION=!TARGET_SYSMON_VERSION:v=!"
        CALL :log "INFO" "action='get_target_version' status='success' version='!TARGET_SYSMON_VERSION!'"
    )
    GOTO :EOF

:get_installed_version
    SET "INSTALLED_VERSION="
    REM --- This subroutine should only be called if the service is confirmed to exist.
    IF NOT EXIST "%INSTALLED_SYSMON_EXE%" ( 
        GOTO :EOF 
    )
    REM --- Read version from the executable currently installed on the system.
    "%INSTALLED_SYSMON_EXE%" > "%TEMP_OUTPUT_FILE%" 2>&1
    IF NOT EXIST "%TEMP_OUTPUT_FILE%" ( GOTO :EOF )
    FOR /F "tokens=3" %%v IN ('findstr /B "System Monitor" "%TEMP_OUTPUT_FILE%"') DO ( SET "INSTALLED_VERSION=%%v" )
    IF DEFINED INSTALLED_VERSION ( 
        SET "INSTALLED_VERSION=!INSTALLED_VERSION:v=!"
        CALL :log "INFO" "action='get_installed_version' status='success' version='!INSTALLED_VERSION!'"
    ) ELSE (
        CALL :log "WARN" "action='get_installed_version' status='read_failed'"
    )
    GOTO :EOF

:log
    REM --- A simple logging function.
    REM --- %~1 is the log level (e.g., INFO, ERROR)
    REM --- %~2 is the log message string
    ECHO timestamp="%DATE% %TIME%" level="%~1" %~2 >> "%LOG_FILE%"
    GOTO :EOF

ENDLOCAL
