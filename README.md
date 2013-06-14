# DCI in Haxe
[Haxe](http://haxe.org) is a nice multiplatform language which in its third release (May 2013), enables a complete DCI implementation. If you don't know what DCI is, go to [fulloo.info](http://fulloo.info) for documentation, details, overview and more.

## Short introduction
DCI stands for Data, Context, Interaction. One of the key aspects of DCI is to separate what a system *is* (form, class properties) from what it *does* (function, methods). Form and function has very different rates of change so they should be separated, not as it currently is, put in classes together.

A Context rounds up Data objects that take on the part as Roles, then an Interaction takes place as a flow of messages through the Roles. The Roles define a network of communicating objects and the Role methods force the objects to collaborate according to the distributed interaction algorithm.

([fulloo.info](http://fulloo.info) is your friend if this sounds confusing)

## Download and Install
Install via [haxelib](http://haxe.org/doc/haxelib/using_haxelib):
`haxelib install haxedci`

Then put `-lib haxedci` into your hxml.

## Example/Demo
Clone the [haxedci-example](https://github.com/ciscoheat/haxedci-example) repository, then open the FlashDevelop project file or just execute run.bat (or run if you're on Linux). Also checkout the README file in that repository, it has an introduction to DCI.
