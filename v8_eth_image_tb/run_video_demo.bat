@echo off
echo =========================================================
echo    MO PHONG VIDEO END-TO-END (3 FRAMES GIF ANIMATION)
echo =========================================================
echo.

if not exist "output_log" mkdir output_log

echo [1/3] Tao video 3 frames (qua bong di chuyen) sang ma Hex...
C:\Users\siplab\AppData\Local\Programs\Python\Python312\python.exe video2hex.py
echo.

echo [2/3] Chay mo phong ModelSim...
echo Xin hay kien nhan, mo phong 3 khung hinh 640x480 se mat khoang 10-15 phut!
C:\altera\13.0sp1\modelsim_ase\win32aloem\vsim.exe -c -do run_headless.do
echo.

echo [3/3] Ghep cac ma mau tu ModelSim thanh file GIF...
C:\Users\siplab\AppData\Local\Programs\Python\Python312\python.exe hex2video.py
echo.

echo HOAN THANH! Ban hay mo file "reconstructed_video.mp4" len de xem ket qua di chuyen nhe!
pause
