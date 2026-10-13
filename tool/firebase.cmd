@echo off
setlocal
pushd "%~dp0.."
set "taskFirebaseNode="
for /d %%D in (".tools\node-*-win-x64") do if exist "%%~fD\node.exe" set "taskFirebaseNode=%%~fD\node.exe"
if defined taskFirebaseNode if exist "firebase_tests\node_modules\firebase-tools\lib\bin\firebase.js" goto localCli
call firebase %*
goto done
:localCli
"%taskFirebaseNode%" "firebase_tests\node_modules\firebase-tools\lib\bin\firebase.js" %*
:done
set "taskFirebaseResult=%errorlevel%"
popd
exit /b %taskFirebaseResult%
