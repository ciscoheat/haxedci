# DCI in Haxe
[Haxe](http://haxe.org) is a nice multiplatform language which enables a full DCI implementation. If you don't know what DCI is, keep reading, you're in for a treat!

## Short introduction
DCI stands for Data, Context, Interaction. One of the key aspects of DCI is to separate what a system *is* (data) from what it *does* (function). Data and function has very different rates of change so they should be separated, not as it currently is, put in classes together. Another aspect is a clear and direct mapping from the user's mental mode to code.

## Download and Install
Install via [haxelib](http://haxe.org/doc/haxelib/using_haxelib): `haxelib install haxedci`

Then put `-lib haxedci` into your hxml.

## Example/Demo
Browse to the [haxedci-example](https://github.com/ciscoheat/haxedci-example) repository for a syntax explanation of the library, a longer introduction to DCI, and a downloadable demo.

## Special features
Because of the special syntax, there are problems with autocompletion for Roles so it is done through an external file. In your source directory a file called "dci-signatures.bin" will be generated. This only happens in debug mode, and if you want control over the location you can set the flag `-D dci-signatures=your_file.txt` (or even `-D dci-signatures=` if you want to disable it completely.)

There are still some issues with using "this" inside a RoleMethod that seems hard to fix, in case you see some extra methods appended to the Context object.

Finally you will only get autocompletion for RoleMethods if you set a return value explicitly. If you want warnings for the occational slip of mind (also debug mode only), define `-D dci-signatures-warnings`.

## DCI Resources
**Recommended:** [DCI – How to get ahead in system architecture](http://www.silexlabs.org/wwx2014-speech-andreas-soderlund-dci-how-to-get-ahead-in-system-architecture/) - My DCI speech.

Website - [fulloo.info](http://fulloo.info) <br>
FAQ - [DCI FAQ](http://fulloo.info/doku.php?id=faq) <br>
Support - [stackoverflow](http://stackoverflow.com/questions/tagged/dci), tagging the question with **dci** <br>
Discussions - [Object-composition](https://groups.google.com/forum/?fromgroups#!forum/object-composition) <br>
Wikipedia - [DCI entry](http://en.wikipedia.org/wiki/Data,_Context,_and_Interaction)
