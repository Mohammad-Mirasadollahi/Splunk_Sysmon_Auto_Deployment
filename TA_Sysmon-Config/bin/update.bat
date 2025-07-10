@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

SET APP_NAME=TA-Sysmon-Config
SET LOG_FILE=%WINDIR%\sysmon_config_updater.log
SET LOCAL_SYSMON_EXE=%WINDIR%\sysmon.exe
SET LOCAL_CONFIG_FILE=%WINDIR%\config.xml
SET SCRIPT_VERSION=2.0
SET MAX_RETRIES=3
SET DEPENDENCY_WAIT_TIME=30

REM Initialize logging
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
    
    REM Step 1: Check dependencies with retry logic
    CALL :check_dependencies_with_retry
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='dependency_check' status='failed_final'"
        ECHO ERROR: Required dependencies not available
        EXIT /B 1
    )
    
    REM Step 2: Deploy new configuration
    CALL :get_splunk_path
    IF NOT DEFINED SPLUNKPATH (
        CALL :log "ERROR" "action='find_splunk_path' status='fatal' message='SplunkForwarder not found'"
        ECHO ERROR: SplunkForwarder installation not found
        EXIT /B 1
    )
    
    SET DEPLOY_CONFIG_PATH="%SPLUNKPATH%\etc\apps\%APP_NAME%\bin\config.xml"
    
    REM Step 3: Deploy new configuration with retry
    CALL :deploy_config_with_retry
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='deploy_config' status='failed_final'"
        EXIT /B 1
    )
    
    REM Step 4: Apply configuration to Sysmon
    CALL :apply_sysmon_config
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='apply_config' status='failed'"
        EXIT /B 1
    )
    
    REM Step 5: Verify configuration
    CALL :verify_config_applied
    
    CALL :log "INFO" "action='main_execution' status='completed'"
    ECHO SUCCESS: Sysmon configuration updated successfully
    EXIT /B 0

:check_admin_privileges
    NET SESSION >NUL 2>&1
    EXIT /B %ERRORLEVEL%

:check_dependencies_with_retry
    SET RETRY_COUNT=0
    
    :retry_dependency_check
    IF %RETRY_COUNT% GEQ %MAX_RETRIES% (
        CALL :log "ERROR" "action='dependency_check' status='max_retries_exceeded' retries='%RETRY_COUNT%'"
        EXIT /B 1
    )
    
    SET /A RETRY_COUNT+=1
    CALL :log "INFO" "action='dependency_check' status='attempt' retry='%RETRY_COUNT%'"
    
    REM Check if sysmon.exe exists
    IF NOT EXIST %LOCAL_SYSMON_EXE% (
        CALL :log "WARN" "action='dependency_check' status='sysmon_missing' retry='%RETRY_COUNT%' message='sysmon.exe not found'"
        ECHO WARNING: sysmon.exe not found, waiting for TA-Sysmon-Binary... (Attempt %RETRY_COUNT%/%MAX_RETRIES%)
        TIMEOUT /T %DEPENDENCY_WAIT_TIME% /NOBREAK >NUL
        GOTO :retry_dependency_check
    )
    
    REM Check if Sysmon service is running
    SC query Sysmon >NUL 2>&1
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "WARN" "action='dependency_check' status='service_missing' retry='%RETRY_COUNT%' message='Sysmon service not found'"
        ECHO WARNING: Sysmon service not found, waiting... (Attempt %RETRY_COUNT%/%MAX_RETRIES%)
        TIMEOUT /T %DEPENDENCY_WAIT_TIME% /NOBREAK >NUL
        GOTO :retry_dependency_check
    )
    
    SC query Sysmon | find "RUNNING" >NUL 2>&1
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "WARN" "action='dependency_check' status='service_not_running' retry='%RETRY_COUNT%' message='Sysmon service not running'"
        ECHO WARNING: Sysmon service not running, waiting... (Attempt %RETRY_COUNT%/%MAX_RETRIES%)
        TIMEOUT /T %DEPENDENCY_WAIT_TIME% /NOBREAK >NUL
        GOTO :retry_dependency_check
    )
    
    CALL :log "INFO" "action='dependency_check' status='success' retry='%RETRY_COUNT%'"
    ECHO INFO: Dependencies verified successfully
    EXIT /B 0

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
                GOTO :splunk_found_config
            )
        )
    )
    
    :splunk_found_config
    IF DEFINED SPLUNKPATH (
        CALL :log "INFO" "action='find_splunk_path' status='success' method='%SPLUNK_PATH_METHOD%' path='!SPLUNKPATH!'"
        ECHO INFO: Found Splunk at: !SPLUNKPATH!
    ) ELSE (
        CALL :log "ERROR" "action='find_splunk_path' status='failed' message='Splunk installation not found'"
    )
    EXIT /B 0

:deploy_config_with_retry
    SET RETRY_COUNT=0
    
    :retry_config_deploy
    IF %RETRY_COUNT% GEQ %MAX_RETRIES% (
        CALL :log "ERROR" "action='deploy_config' status='max_retries_exceeded' retries='%RETRY_COUNT%'"
        EXIT /B 1
    )
    
    SET /A RETRY_COUNT+=1
    CALL :log "INFO" "action='deploy_config' status='attempt' retry='%RETRY_COUNT%'"
    
    REM Check if source config file exists
    IF NOT EXIST %DEPLOY_CONFIG_PATH% (
        CALL :log "ERROR" "action='deploy_config' status='source_missing' file='%DEPLOY_CONFIG_PATH%'"
        ECHO ERROR: Source config.xml not found in deployment package
        EXIT /B 1
    )
    
    COPY /Y %DEPLOY_CONFIG_PATH% %LOCAL_CONFIG_FILE% >NUL 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :log "INFO" "action='deploy_config' status='success' retry='%RETRY_COUNT%'"
        ECHO INFO: Configuration file deployed successfully
        EXIT /B 0
    )
    
    CALL :log "WARN" "action='deploy_config' status='retry_needed' retry='%RETRY_COUNT%' error='%ERRORLEVEL%'"
    TIMEOUT /T 2 /NOBREAK >NUL
    GOTO :retry_config_deploy

:apply_sysmon_config
    CALL :log "INFO" "action='apply_config' status='starting'"
    ECHO INFO: Applying new Sysmon configuration...
    
    REM Apply configuration with timeout
    TIMEOUT /T 2 /NOBREAK >NUL
    %LOCAL_SYSMON_EXE% -c %LOCAL_CONFIG_FILE% >NUL 2>&1
    SET CONFIG_RESULT=%ERRORLEVEL%
    
    IF %CONFIG_RESULT% EQU 0 (
        CALL :log "INFO" "action='apply_config' status='success'"
        ECHO SUCCESS: Sysmon configuration applied successfully
    ) ELSE (
        CALL :log "ERROR" "action='apply_config' status='failed' error_code='%CONFIG_RESULT%'"
        ECHO ERROR: Failed to apply Sysmon configuration
    )
    
    EXIT /B %CONFIG_RESULT%

:verify_config_applied
    CALL :log "INFO" "action='verify_config' status='starting'"
    
    REM Check if service is still running after config change
    SC query Sysmon | find "RUNNING" >NUL 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :log "INFO" "action='verify_config' status='service_running'"
        ECHO INFO: Sysmon service is running with new configuration
    ) ELSE (
        CALL :log "WARN" "action='verify_config' status='service_not_running'"
        ECHO WARNING: Sysmon service is not running after configuration change
    )
    
    REM Verify config file exists and is not empty
    IF EXIST %LOCAL_CONFIG_FILE% (
        FOR %%F IN (%LOCAL_CONFIG_FILE%) DO (
            IF %%~zF GTR 0 (
                CALL :log "INFO" "action='verify_config' status='config_file_ok' size='%%~zF'"
            ) ELSE (
                CALL :log "ERROR" "action='verify_config' status='config_file_empty'"
            )
        )
    ) ELSE (
        CALL :log "ERROR" "action='verify_config' status='config_file_missing'"
    )
    
    EXIT /B 0

:log
    REM Enhanced logging with better timestamp format
    SET LOG_TIMESTAMP=%DATE:~-4%-%DATE:~4,2%-%DATE:~7,2% %TIME:~0,8%
    ECHO [%LOG_TIMESTAMP%] [%~1] %~2 >> "%LOG_FILE%"
    EXIT /B 0

ENDLOCAL
