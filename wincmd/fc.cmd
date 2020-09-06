@echo off
if not x%2 == x goto usage

:checkFirstArg 
if y%1 == y goto usage

for /F "tokens=*" %%j in ('dir *.jar /b /s') do (
echo %%j
jar tvf %%j | findstr "%1")

goto endofLife

:usage
echo "fc {arg}"
goto endofLife

:endofLife