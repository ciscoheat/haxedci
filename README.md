# DCI in Haxe
[Haxe](http://haxe.org) is a nice multiplatform language which in its third release (May 2013), enables a complete DCI implementation. If you don't know what DCI is, go to [fulloo.info](http://fulloo.info) for documentation, details, overview and more.

## Short introduction
DCI stands for Data, Context, Interaction. One of the key aspects of DCI is to separate what a system *is* (data) from what it *does* (function). Data and function has very different rates of change so they should be separated, not as it currently is, put in classes together.

## Download and Install
Install via [haxelib](http://haxe.org/doc/haxelib/using_haxelib):
`haxelib install haxedci`

Then put `-lib haxedci` into your hxml.

## Example/Demo
Clone the [haxedci-example](https://github.com/ciscoheat/haxedci-example) repository, then open the FlashDevelop project file or just execute run.bat (or run if you're on Linux). Also checkout the README file in that repository, it has an introduction to DCI.

## Special features
When you compile, [sequence diagrams](http://en.wikipedia.org/wiki/Sequence_diagram) will automatically be generated for the Contexts, placed in the `bin/dcigraphs` directory. Quite useful for visualizing the distributed algorithm in a Context, and how the Roles interact with each other. If you don't want this feature, you can turn it off by compiling with `-D nodcigraphs`.
