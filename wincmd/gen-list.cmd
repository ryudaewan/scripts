@echo off
echo ^<hmtl lang=^"ko^"^>^<head^>^<meta charset^=^"euc-kr^" /^>^<style^>table { width: 95%%; border: 1px solid #444444;
echo border-collapse: collapse;} th, td { border: 1px solid #444444; padding: 10px; }^</style^>^</head^>
echo ^<body^>^<div id^=^"deliverables-list^"^>^<p^>^<table^>^<thead^>^<tr^>
echo ^<th^>Path^</th^>^<th^>Name^</th^>^</tr^>^</thead^>^<tbody^>
for /F "usebackq tokens=* delims=<" %%A in (`dir /b /s /a:a ^| findstr /v \.svn\`) do (
echo ^<tr^>^<td^>^<a href=^"%%~dA%%~pA^"^>%%~dA%%~pA^</a^>^</td^>^<td^>^<a href=^"%%~fA^"^>%%~nA%%~xA^</a^>^</td^>^</tr^> )
echo ^</tbody^>^</table^>^</p^>^</div^>^</body^>^</html^>
