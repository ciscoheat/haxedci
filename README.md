# DCI in Haxe
[Haxe](http://haxe.org) is a nice multiplatform language which enables a full DCI implementation. If you don't know what DCI is, keep reading, you're in for a treat!

## Short introduction
DCI stands for Data, Context, Interaction. One of the key aspects of DCI is to separate what a system *is* (data) from what it *does* (function). Data and function has very different rates of change so they should be separated, not as it currently is, put in classes together. Another aspect is a clear and direct mapping from the user's mental mode to code.

## Download and Install
Install via [haxelib](http://haxe.org/doc/haxelib/using_haxelib): `haxelib install haxedci`

Then put `-lib haxedci` into your hxml.

## Example/Demo
Browse to the [haxedci-example](https://github.com/ciscoheat/haxedci-example) repository for a syntax explanation of the library, a longer introduction to DCI, and a downloadable demo.

## Notes
Because of the special syntax, there are some problems with autocompletion for Roles. When inside a Role, not all of its RoleMethods may show up. The compiler seems to stop early. Also you will only get autocompletion for RoleMethods if you set a return value explicitly. If you want warnings for the occational slip of mind (debug mode only), define `-D dci-signatures-warnings`.

## DCI Resources
**Recommended:** [DCI – How to get ahead in system architecture](http://www.silexlabs.org/wwx2014-speech-andreas-soderlund-dci-how-to-get-ahead-in-system-architecture/) - My DCI speech.

Website - [fulloo.info](http://fulloo.info) <br>
FAQ - [DCI FAQ](http://fulloo.info/doku.php?id=faq) <br>
Support - [stackoverflow](http://stackoverflow.com/questions/tagged/dci), tagging the question with **dci** <br>
Discussions - [Object-composition](https://groups.google.com/forum/?fromgroups#!forum/object-composition) <br>
Wikipedia - [DCI entry](http://en.wikipedia.org/wiki/Data,_Context,_and_Interaction)
