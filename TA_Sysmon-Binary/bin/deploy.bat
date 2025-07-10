@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

SET APP_NAME=TA-Sysmon-Binary
SET LOG_FILE=%WINDIR%\sysmon_installer.log
SET LOCAL_SYSMON_EXE=%WINDIR%\sysmon.exe
SET SCRIPT_VERSION=2.0
SET MAX_RETRIES=3

REM Initialize logging with script start
CALL :log "INFO" "action='script_start' script_version='%SCRIPT_VERSION%' app_name='%APP_NAME%' timestamp='%DATE% %TIME%'"

REM Check if running as Administrator
CALL :check_admin_privileges
IF %ERRORLEVEL% NEQ 0 (
    CALL :log "ERROR" "action='admin_check' status='failed' message='Script requires Administrator privileges'"
    ECHO ERROR: This script must be run as Administrator
    PAUSE
    EXIT /B 1
)

REM Main execution flow
CALL :main_execution
EXIT /B %ERRORLEVEL%

:main_execution
    CALL :log "INFO" "action='main_execution' status='started'"
    
    REM Step 1: Find Splunk installation
    CALL :get_splunk_path
    IF NOT DEFINED SPLUNKPATH (
        CALL :log "ERROR" "action='find_splunk_path' status='fatal' message='SplunkForwarder not found'"
        ECHO ERROR: SplunkForwarder installation not found
        EXIT /B 1
    )
    
    REM Step 2: Read target version from config
    CALL :read_target_version
    IF NOT DEFINED TARGET_SYSMON_VERSION (
        CALL :log "ERROR" "action='read_target_version' status='failed' message='Cannot read target version'"
        EXIT /B 1
    )
    
    REM Step 3: Validate deployment files
    CALL :validate_deployment_files
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='validate_files' status='failed'"
        EXIT /B 1
    )
    
    REM Step 4: Copy binary to system directory
    CALL :copy_binary_with_retry
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='copy_binary' status='failed_final'"
        EXIT /B 1
    )
    
    REM Step 5: Check current installation and determine action
    CALL :get_installed_version
    CALL :determine_action
    
    REM Step 6: Execute determined action
    IF "!ACTION!"=="INSTALL" (
        CALL :install_service
    ) ELSE IF "!ACTION!"=="UPGRADE" (
        CALL :upgrade_service
    ) ELSE IF "!ACTION!"=="SKIP" (
        CALL :log "INFO" "action='version_check' status='up_to_date' message='No action needed'"
        ECHO INFO: Sysmon is already up to date
    )
    
    REM Step 7: Verify installation
    CALL :verify_installation
    
    CALL :log "INFO" "action='main_execution' status='completed'"
    ECHO SUCCESS: Sysmon deployment completed successfully
    EXIT /B 0

:check_admin_privileges
    NET SESSION >NUL 2>&1
    EXIT /B %ERRORLEVEL%

:get_splunk_path
    SET SPLUNK_PATH_METHOD=N/A
    SET SPLUNKPATH=
    
    REM Method 1: Try WMI service query
    FOR /F "tokens=1,2,*" %%a IN ('wmic service SplunkForwarder get PathName /value 2^>NUL ^| find "PathName"') DO (
        SET SPLUNKDPATH=%%c
        IF DEFINED SPLUNKDPATH (
            SET SPLUNKPATH=!SPLUNKDPATH:"=!
            SET SPLUNKPATH=!SPLUNKPATH:~0,-28!
            SET SPLUNK_PATH_METHOD=WMI
        )
    )
    
    REM Method 2: Try registry if WMI failed
    IF NOT DEFINED SPLUNKPATH (
        FOR /F "tokens=2*" %%a IN ('reg query "HKLM\SOFTWARE\Splunk\SplunkUniversalForwarder" /v InstallPath 2^>NUL ^| find "InstallPath"') DO (
            SET SPLUNKPATH=%%b
            IF DEFINED SPLUNKPATH (SET SPLUNK_PATH_METHOD=Registry)
        )
    )
    
    REM Method 3: Try common installation paths
    IF NOT DEFINED SPLUNKPATH (
        FOR %%p IN ("C:\Program Files\SplunkUniversalForwarder" "C:\Program Files (x86)\SplunkUniversalForwarder") DO (
            IF EXIST "%%~p\bin\splunk.exe" (
                SET SPLUNKPATH=%%~p
                SET SPLUNK_PATH_METHOD=FileSystem
                GOTO :splunk_found
            )
        )
    )
    
    :splunk_found
    IF DEFINED SPLUNKPATH (
        CALL :log "INFO" "action='find_splunk_path' status='success' method='%SPLUNK_PATH_METHOD%' path='!SPLUNKPATH!'"
        ECHO INFO: Found Splunk at: !SPLUNKPATH!
    ) ELSE (
        CALL :log "ERROR" "action='find_splunk_path' status='failed' message='Splunk installation not found'"
    )
    EXIT /B 0

:read_target_version
    SET VERSION_CONFIG_FILE="%SPLUNKPATH%\etc\apps\%APP_NAME%\default\sysmon_version.conf"
    SET TARGET_SYSMON_VERSION=
    
    IF NOT EXIST %VERSION_CONFIG_FILE% (
        CALL :log "ERROR" "action='read_target_version' status='file_missing' file='%VERSION_CONFIG_FILE%'"
        EXIT /B 1
    )
    
    FOR /F "tokens=2 delims==" %%v IN ('type %VERSION_CONFIG_FILE% 2^>NUL ^| find "version"') DO (
        SET TARGET_SYSMON_VERSION=%%v
    )
    
    IF DEFINED TARGET_SYSMON_VERSION (
        SET TARGET_SYSMON_VERSION=!TARGET_SYSMON_VERSION: =!
        CALL :log "INFO" "action='read_target_version' status='success' version='!TARGET_SYSMON_VERSION!'"
        ECHO INFO: Target Sysmon version: !TARGET_SYSMON_VERSION!
    ) ELSE (
        CALL :log "ERROR" "action='read_target_version' status='failed' message='Version not found in config'"
    )
    EXIT /B 0

:validate_deployment_files
    SET DEPLOY_BINARY_PATH="%SPLUNKPATH%\etc\apps\%APP_NAME%\bin\sysmon.exe"
    SET DEPLOY_CONFIG_PATH="%SPLUNKPATH%\etc\apps\%APP_NAME%\bin\config.xml"
    
    IF NOT EXIST %DEPLOY_BINARY_PATH% (
        CALL :log "ERROR" "action='validate_files' status='missing_binary' file='%DEPLOY_BINARY_PATH%'"
        ECHO ERROR: sysmon.exe not found in deployment package
        EXIT /B 1
    )
    
    IF NOT EXIST %DEPLOY_CONFIG_PATH% (
        CALL :log "WARN" "action='validate_files' status='missing_config' file='%DEPLOY_CONFIG_PATH%'"
        ECHO WARNING: config.xml not found in deployment package
    )
    
    CALL :log "INFO" "action='validate_files' status='success'"
    EXIT /B 0

:copy_binary_with_retry
    SET RETRY_COUNT=0
    
    :retry_copy
    IF %RETRY_COUNT% GEQ %MAX_RETRIES% (
        CALL :log "ERROR" "action='copy_binary' status='max_retries_exceeded' retries='%RETRY_COUNT%'"
        EXIT /B 1
    )
    
    SET /A RETRY_COUNT+=1
    CALL :log "INFO" "action='copy_binary' status='attempt' retry='%RETRY_COUNT%'"
    
    COPY /Y %DEPLOY_BINARY_PATH% %LOCAL_SYSMON_EXE% >NUL 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :log "INFO" "action='copy_binary' status='success' retry='%RETRY_COUNT%'"
        ECHO INFO: Binary copied successfully
        EXIT /B 0
    )
    
    CALL :log "WARN" "action='copy_binary' status='retry_needed' retry='%RETRY_COUNT%' error='%ERRORLEVEL%'"
    TIMEOUT /T 2 /NOBREAK >NUL
    GOTO :retry_copy

:get_installed_version
    SET ESCAPED_LOCAL_SYSMON_EXE=%WINDIR%\\sysmon.exe
    SET INSTALLED_VERSION=
    SET VERSION_METHOD=N/A
    
    IF NOT EXIST %LOCAL_SYSMON_EXE% (
        CALL :log "INFO" "action='get_version' status='no_existing_installation'"
        EXIT /B 0
    )
    
    REM Method 1: Try WMI file version
    FOR /F "tokens=2 delims==" %%v IN ('wmic datafile where name^="%ESCAPED_LOCAL_SYSMON_EXE%" get Version /value 2^>NUL ^| find "Version"') DO (
        SET INSTALLED_VERSION=%%v
        IF DEFINED INSTALLED_VERSION (SET VERSION_METHOD=WMI)
    )
    
    REM Method 2: Try executable output if WMI failed
    IF NOT DEFINED INSTALLED_VERSION (
        FOR /F "tokens=4" %%v IN ('%LOCAL_SYSMON_EXE% -nobanner 2^>NUL') DO (
            SET INSTALLED_VERSION=%%v
            IF DEFINED INSTALLED_VERSION (
                SET INSTALLED_VERSION=!INSTALLED_VERSION:v=!
                SET VERSION_METHOD=Executable
            )
        )
    )
    
    IF DEFINED INSTALLED_VERSION (
        CALL :log "INFO" "action='get_version' status='success' method='%VERSION_METHOD%' version='!INSTALLED_VERSION!'"
        ECHO INFO: Current Sysmon version: !INSTALLED_VERSION!
    ) ELSE (
        CALL :log "WARN" "action='get_version' status='failed' message='Could not determine version'"
    )
    EXIT /B 0

:determine_action
    SET ACTION=INSTALL
    
    IF NOT DEFINED INSTALLED_VERSION (
        SET ACTION=INSTALL
        CALL :log "INFO" "action='determine_action' decision='INSTALL' reason='no_existing_version'"
    ) ELSE IF "!INSTALLED_VERSION!"=="!TARGET_SYSMON_VERSION!" (
        SET ACTION=SKIP
        CALL :log "INFO" "action='determine_action' decision='SKIP' reason='versions_match'"
    ) ELSE (
        SET ACTION=UPGRADE
        CALL :log "INFO" "action='determine_action' decision='UPGRADE' reason='version_mismatch' current='!INSTALLED_VERSION!' target='!TARGET_SYSMON_VERSION!'"
    )
    EXIT /B 0

:install_service
    CALL :log "INFO" "action='install_service' status='starting'"
    ECHO INFO: Installing Sysmon service...
    
    %LOCAL_SYSMON_EXE% -accepteula -i %DEPLOY_CONFIG_PATH% >NUL 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :log "INFO" "action='install_service' status='success'"
        ECHO SUCCESS: Sysmon service installed successfully
    ) ELSE (
        CALL :log "ERROR" "action='install_service' status='failed' error_code='%ERRORLEVEL%'"
        ECHO ERROR: Sysmon service installation failed
    )
    EXIT /B %ERRORLEVEL%

:upgrade_service
    CALL :log "INFO" "action='upgrade_service' status='starting' old_version='!INSTALLED_VERSION!' new_version='!TARGET_SYSMON_VERSION!'"
    ECHO INFO: Upgrading Sysmon service...
    
    REM Uninstall old version
    CALL :log "INFO" "action='upgrade_service' status='uninstalling_old'"
    %LOCAL_SYSMON_EXE% -u force >NUL 2>&1
    
    REM Wait a moment for service to fully stop
    TIMEOUT /T 3 /NOBREAK >NUL
    
    REM Install new version
    CALL :log "INFO" "action='upgrade_service' status='installing_new'"
    %LOCAL_SYSMON_EXE% -accepteula -i %DEPLOY_CONFIG_PATH% >NUL 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :log "INFO" "action='upgrade_service' status='success'"
        ECHO SUCCESS: Sysmon service upgraded successfully
    ) ELSE (
        CALL :log "ERROR" "action='upgrade_service' status='failed' error_code='%ERRORLEVEL%'"
        ECHO ERROR: Sysmon service upgrade failed
    )
    EXIT /B %ERRORLEVEL%

:verify_installation
    CALL :log "INFO" "action='verify_installation' status='starting'"
    
    REM Check if service is running
    SC query Sysmon >NUL 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :log "INFO" "action='verify_installation' status='service_exists'"
        
        REM Check service status
        FOR /F "tokens=3" %%s IN ('sc query Sysmon ^| find "STATE"') DO (
            IF "%%s"=="RUNNING" (
                CALL :log "INFO" "action='verify_installation' status='success' service_state='RUNNING'"
                ECHO INFO: Sysmon service is running
            ) ELSE (
                CALL :log "WARN" "action='verify_installation' status='service_not_running' service_state='%%s'"
                ECHO WARNING: Sysmon service exists but is not running
            )
        )
    ) ELSE (
        CALL :log "ERROR" "action='verify_installation' status='service_not_found'"
        ECHO ERROR: Sysmon service not found after installation
    )
    EXIT /B 0

:log
    REM Enhanced logging with better timestamp format
    SET LOG_TIMESTAMP=%DATE:~-4%-%DATE:~4,2%-%DATE:~7,2% %TIME:~0,8%
    ECHO [%LOG_TIMESTAMP%] [%~1] %~2 >> "%LOG_FILE%"
    EXIT /B 0

ENDLOCAL
