@echo off
echo =========================================================
echo    MO PHONG END-TO-END: PC (Image) -^> ETH -^> SDRAM -^> VGA
echo =========================================================
echo.

if not exist "output_log" mkdir output_log

echo [1/3] Tao buc anh 640x480 mau va chuyen doi sang ma Hex...
C:\Users\siplab\AppData\Local\Programs\Python\Python312\python.exe img2hex.py
echo.

echo [2/3] Chay mo phong ModelSim...
echo Xin hay kien nhan, qua trinh mo phong 640x480 se mat khoang 3-5 phut!
C:\altera\13.0sp1\modelsim_ase\win32aloem\vsim.exe -c -do run_headless.do
echo.

echo [3/3] Ghep cac ma mau tu ModelSim thanh buc anh dau ra...
C:\Users\siplab\AppData\Local\Programs\Python\Python312\python.exe hex2img.py
echo.

echo HOAN THANH! Ban hay mo file "reconstructed_output.jpg" len de xem ket qua.
pause
