@echo off
setlocal
title Monchi - Construir APK
cd /d "%~dp0"

echo.
echo  ===============================================
echo    Monchi - construyendo el APK
echo  ===============================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
  echo No se encontro Flutter. Instala Flutter y agregalo al PATH.
  goto :error
)

rem Stop old Gradle processes that were started with too much memory.
if exist "android\gradlew.bat" (
  pushd android
  call gradlew.bat --stop >nul 2>nul
  popd
)

echo [1/4] Descargando librerias...
call flutter pub get
if errorlevel 1 goto :error

echo [2/4] Generando codigo de la base de datos...
call dart run build_runner build --delete-conflicting-outputs
if errorlevel 1 goto :error

echo [3/4] Compilando el APK (la primera vez tarda varios minutos)...
call flutter build apk --release
if errorlevel 1 goto :error

echo [4/4] Copiando el APK...
if not exist "..\APK" mkdir "..\APK"
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "..\APK\ExpenseManager.apk" >nul
if errorlevel 1 goto :error

if not exist "android\key.properties" (
  echo.
  echo AVISO: no hay llave de firma ^(android\key.properties^). El APK se firmo con una
  echo llave de prueba: futuras versiones podrian no instalarse encima de esta.
)

echo.
echo  LISTO. Tu APK esta en: APK\ExpenseManager.apk
echo  Copialo al telefono e instalalo.
echo.
explorer "..\APK"
pause
exit /b 0

:error
echo.
echo  La compilacion fallo. Copia el texto de arriba y enviaselo a Claude.
echo.
pause
exit /b 1
