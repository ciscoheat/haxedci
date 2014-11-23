# DCI in Haxe
[Haxe](http://haxe.org) is a nice multiplatform language which enables a full DCI implementation. If you don't know what DCI is, keep reading, you're in for a treat!

## Short introduction
DCI stands for Data, Context, Interaction. One of the key aspects of DCI is to separate what a system *is* (data) from what it *does* (function). Data and function has very different rates of change so they should be separated, not as it currently is, put in classes together.

## Download and Install
Install via [haxelib](http://haxe.org/doc/haxelib/using_haxelib):
`haxelib install haxedci`

Then put `-lib haxedci` into your hxml.

## Example/Demo
Browse to the [haxedci-example](https://github.com/ciscoheat/haxedci-example) repository for a longer introduction to DCI, and a downloadable demo.

## Special features
If you compile with the flag `-D dcigraphs`, [sequence diagrams](http://en.wikipedia.org/wiki/Sequence_diagram) will automatically be generated for the Contexts, placed in the `bin/dcigraphs` directory. Useful for visualizing the distributed algorithm in a Context, and how the Roles interact with each other.

## DCI Resources
**Recommended:** [DCI – How to get ahead in system architecture](http://www.silexlabs.org/wwx2014-speech-andreas-soderlund-dci-how-to-get-ahead-in-system-architecture/) - My latest DCI speech.

Website - [fulloo.info](http://fulloo.info) <br>
FAQ - [DCI FAQ](http://fulloo.info/doku.php?id=faq) <br>
Support - [stackoverflow](http://stackoverflow.com/questions/tagged/dci), tagging the question with **dci** <br>
Discussions - [Object-composition](https://groups.google.com/forum/?fromgroups#!forum/object-composition) <br>
Wikipedia - [DCI entry](http://en.wikipedia.org/wiki/Data,_Context,_and_Interaction)
