@echo off
del haxedci.zip >nul 2>&1

cd src
copy ..\README.md .
zip -r ..\haxedci.zip .
del README.md
cd ..

haxelib submit haxedci.zip
del haxedci.zip
