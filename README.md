# DCI in Haxe

[Haxe](http://haxe.org) is a nice multiplatform language which enables a full DCI implementation. If you don't know what DCI is, keep reading, you're in for a treat!

## Short introduction

DCI stands for Data, Context, Interaction. The key aspects of the DCI architecture are:

- Separating what the system *is* (data) from what it *does* (function). Data and function have different rates of change so they should be separated, not as it currently is, put in classes together.
- Create a direct mapping from the user's mental model to code. The computer should think as the user, not the other way around.
- Make system behavior a first class entity.
- Great code readability with no surprises at runtime.

## Download and Install

Install via [haxelib](http://haxe.org/doc/haxelib/using_haxelib): `haxelib install haxedci`

Then put `-lib haxedci` into your hxml.

# How to use

An ATM money transfer will be our simple DCI example and tutorial. (Thanks to [Marc Grue](https://github.com/marcgrue) for the original money transfer tutorial)

Let's start with a simple data class called `Account`, containing a few methods:

```haxe
class Account {
	public var name(default, null) : String;
	public var balance(default, null) : Int;

	public function new(name, balance) {
		this.name = name;
		this.balance = balance;
	}

	public function increaseBalance(amount: Int) {
		balance += amount;
	}

	public function decreaseBalance(amount: Int) {
		balance -= amount;
	}
}
```

This is what we in DCI sometimes call a "dumb" data class. It only "knows" about its own data and trivial ways to manipulate it. The concept of a transfer between two accounts is outside its responsibilities and we delegate this to a Context - the `MoneyTransfer` Context class. In this way we can keep the Account class very slim and avoid that it gradually takes on more and more responsibilities for each use case it participates in.

From a users point of view we might think of a money transfer as

- "Move money from one account to another"

and after some more thought specify it further:

- "Withdraw amount from a source account and deposit the amount in a destination account"

That could be our "Mental Model" of a money transfer. Interacting concepts like our "Source" and "Destination" accounts of our mental model we call "Roles" in DCI, and we can define them and what they do to accomplish the money transfer in a DCI Context.

Our source code should map as closely to our mental model as possible so that we can confidently and easily overview and reason about _how the objects will interact at runtime_. We want no surprises at runtime. With DCI we have all runtime interactions right there! No need to look through endless convoluted abstractions, tiers, polymorphism etc to answer the reasonable question _where is it actually happening?!_

## Creating a Context

To use haxedci, you need to be able to create Contexts. Lets build the `MoneyTransfer` class step-by-step from scratch:

Start by defining a class and let it implement `dci.Context`.

```haxe
class MoneyTransfer implements dci.Context {
}
```

Remember the mental model of a money transfer? "Withdraw *amount* from a *source* account and deposit the amount in a *destination* account". The three italicized nouns are the Roles that we will use in the Context. Lets put them there. They are defined using the `@role` metadata:

```haxe
class MoneyTransfer implements dci.Context {
	@role var source : {}
	@role var destination : {}
	@role var amount : {}
}
```

Using this syntax, we have now defined three Roles. Having the type `{}` means that these Roles can be played by any object, but we want to be more specific.

### Defining a RoleObjectContract

In DCI, the type of a Role is called its **RoleObjectContract**, or just **contract**.

The common thinking is to use the already defined classes. The source and destination Roles could be an `Account`.

We're not interested in the whole `Account` however, that is the old, class-oriented thinking. We want to focus on what happens in the Context right now for a specific Role, so all we need for an object to play the *source* Role is a way of decreasing the balance. The `Account` class has a `decreaseBalance` method, which can be useful:

```haxe
@role var source : {
	function decreaseBalance(a : Int) : Void;
}
```

We're using standard [Haxe class notation](http://haxe.org/manual/struct#class-notation) to define the contract. Let's do the same for the *destination* Role, but it needs to increase the balance instead:

```haxe
@role var destination : {
	function increaseBalance(a : Int) : Void;
}
```

The *amount* role is special. We're using an `Int` in this example, which means it can't play a Role. No basic types (`Int`, `Bool`, `Float`, `String`) can play Roles, so we can make it an ordinary var, or pass it as a parameter. Let's use a var in this case.

```haxe
var amount : Int;
```

(In a more realistic example, *amount* would probably have some `Currency` class behind it, enabling it to play a Role.)

Our `MoneyTransfer` Context now looks like this:

```haxe
class MoneyTransfer implements dci.Context {
	@role var source : {
		function decreaseBalance(a : Int) : Void;
	}

	@role var destination : {
		function increaseBalance(a : Int) : Void;
	}

	var amount : Int;
}
```

So what are the advantages of this structural typing? Why not just put the class there and be done with it?

The most obvious advantage is that we're making the Role more generic. Any object fulfilling the type of the RoleObjectContract can now be a money source, not just `Account`.

Another interesting advantage is that when specifying a more compressed contract, we only observe what the Roles can do in the current Context. This is called *"Full OO"*, a powerful concept that you can [read more about here](https://groups.google.com/d/msg/object-composition/umY_w1rXBEw/hyAF-jPgFn4J), but basically, by doing that we don't need to understand `Account`, or essentially anything outside the current Context.

This also affects [locality](http://www.saturnflyer.com/blog/jim/2015/04/21/locality-and-cohesion/), the ability to understand code by looking at only a small portion of it. So plan your public class API, consider what it does, how it's named and why. Then refine your contracts. DCI is as much about clear and readable code as matching a mental model and separating data from function.

### RoleMethods

Now we have the Roles and their contracts for accessing the underlying objects. That's a good start, so lets add the core of a DCI Context: functionality. It is implemented through **RoleMethods**.

Getting back to the mental model again, we know that we want to *"Withdraw amount from a source account and deposit the amount in a destination account"*. So lets model that in a RoleMethod for the `source` Role:

```haxe
@role var source : {
	function decreaseBalance(a : Int) : Void;

	public function withdraw() {
		decreaseBalance(amount);
		destination.deposit();
	}
}
```

The *withdraw* RoleMethod, created as a function with a body, as opposed to contracts which has no body, is a very close mapping of the mental model to code, which is the goal of DCI. 

Note how we're using the contract method only for the actual data operation, the rest is functionality, collaboration between Roles through RoleMethods. This collaboration requires a RoleMethod on destination called `deposit`, according to the mental model. Let's define it:

```haxe
@role var destination : {
	function increaseBalance(a : Int) : Void;

	public function deposit() {
		increaseBalance(amount);
	}
}
```

### Role field access

RoleMethods must be declared `public` to allow access outside the Role. Contract fields should only be accessed from the Role's own RoleMethods however. This enables the ability to trace the flow of cooperation between Roles, instead of any Role being able to call another Role's underlying object at all times. It's a helpful separation between the local reasoning of how Roles interact locally with their object, and how Roles interact with each other. A goal with DCI is readability, and this helps reading and understanding the use-case-level logic of a Context.

There *could* be cases when a calling a contract field from another Role is wanted, so contract fields can also be declared `public`, but accessing them will emit a compiler warning, and its presence should be viewed as a compromise measure that explicitly erodes the readability of the code. It is a way for the programmer to say: *“Trust me”* in spite of the fact that readers of the code can’t verify what goes on behind the curtain.

The exception is if you're using Haxe 4 and the contract field is `final`. Then the field is immutable and can be accessed without warning.

### Accessors: self and this

A RoleMethod is a method with access only to its RolePlayer (through the Role-object contract) and the current Context. You can access the current RolePlayer through the `self` identifier. `this` is not allowed in RoleMethods, as it can create confusion what it really references, the RolePlayer or the Context. Use `self` and the other Role names when referencing them directly.

### Adding a constructor

Let's add a constructor to the class (showing off the `self` identifier as well, and public RoleMethods):

```haxe
class MoneyTransfer implements dci.Context {
	public function new(source, destination, amount) {
		this.source = source;
		this.destination = destination;
		this.amount = amount;
	}

	@role var source : {
		function decreaseBalance(a : Int) : Void;

		public function withdraw() { 
			self.decreaseBalance(amount);
			destination.deposit();
		}
	}

	@role var destination : {
		function increaseBalance(a : Int) : Void;
    
    	function deposit() {
			self.increaseBalance(amount) : Void;
		}
	}

	var amount : Int;
}
```

There's nothing special about the constructor, just assign the Roles as normal instance variables. This is called *Role-binding*, and there are two important things to remember about it:

1. All Roles *must* be bound in the same function.
1. A Role *should not* be left unbound (it can be bound to `null` however).

Rebinding individual Roles during executing complicates things, and is hardly supported by any mental model. So put the binding in one place only, you can factorize it out of the constructor to a separate method if you want. The Roles can be rebound before another Interaction in the same Context occurs, which can be useful during recursion for example, but it must always happen in the same function.

### System Operations

We just mentioned interactions, which is the last part of the DCI acronym. An **Interaction** is a flow of messages through the Roles in a Context, like the one we have defined now, based on the mental model. To start an Interaction we need an entrypoint for the Context, a public method in other words. This is called a **System Operation**, and all it should do is to call a RoleMethod, so the Roles start interacting with each other.

If you're basing the Context on a use case, there is usually only one System Operation in a Context. Let's call it `transfer`. Try not to use a generic name like "execute", instead give your API meaning by letting every method name carry meaningful information.

**MoneyTransfer.hx**

```haxe
class MoneyTransfer implements dci.Context {
	public function new(source, destination, amount) {
		this.source = source;
		this.destination = destination;
		this.amount = amount;
	}

	// System Operation
	public function transfer() {
		source.withdraw();
	}

	@role var source : {
		function decreaseBalance(a : Int) : Void;

		public function withdraw() {
			decreaseBalance(amount);
			destination.deposit();
		}
	}

	@role var destination : {
		function increaseBalance(a : Int) : Void;

		public function deposit() {
			increaseBalance(amount);
		}
	}

	var amount : Int;
}
```

With this System Operation as our entrypoint, the `MoneyTransfer` Context is ready for use! Let's create two accounts and the Context, and finally make the transfer.

**Account.hx**

```haxe
class Account {
    public var name(default, null) : String;
	public var balance(default, null) : Int;

	public function new(name, balance) {
		this.name = name;
		this.balance = balance;
	}

	public function increaseBalance(amount: Int) {
		balance += amount;
	}

	public function decreaseBalance(amount: Int) {
		balance -= amount;
	}
}
```

**Main.hx**

```haxe
class Main {
	static function main() {
		var savings = new Account("Savings", 1000);
		var home = new Account("Home", 0);

		trace("Before transfer:");
		trace(savings.name + ": $" + savings.balance); // 1000
		trace(home.name + ": $" + home.balance); // 0

		// Creating and executing the Context:
		new MoneyTransfer(savings, home, 500).transfer();

		trace("After transfer:");
		trace(savings.name + ": $" + savings.balance); // 500
		trace(home.name + ": $" + home.balance); // 500
	}
}
```

With the above three files, you can now build and test the example with `haxe -lib haxedci -x Main`.

## Fluent interfaces

DCI pays great respect to Alan Kay and Smalltalk, which has a feature popularized in the [fluent interface](https://en.wikipedia.org/wiki/Fluent_interface). See [message passing](http://c2.com/cgi/wiki?AlanKayOnMessaging) and [east-oriented code](http://www.saturnflyer.com/blog/jim/2014/12/23/enforcing-encapsulation-with-east-oriented-code/) for more information.

If you're designing your objects to return "this", enabling a fluent interface, there is a special feature when such an object is playing a Role in a Context:

```haxe
@role var destination : {
	function increaseBalance(a : Int) : dci.Self;
}
```

# Advantages

Ok, we have learned new concepts and a different way of structuring our program. But why should we do all this?

The advantage we get from using Roles and RoleMethods in a Context, is that we know exactly where our functionality is. It's not spread out in multiple classes anymore. When we talk about a "money transfer", we know exactly where in the code it is handled now. Another good thing is that we keep the code simple. No facades, design patterns or other abstractions, just the methods we need.

The Roles and their RoleMethods gives us a view of the Interaction between objects instead of their inner structure. This enables us to reason about *system* functionality, not just class functionality. In other words, DCI embodies true object-orientation where runtime Interactions between a network of objects in a particular Context is understood *and* coded as first class citizens.

We are using the terminology and mental model of the user. We can reason with non-programmers using their terminology, see the responsibility of each Role in the RoleMethods, and follow the mental model as specified within the Context.

DCI is a new paradigm, which forces the mind in different directions than the common OO-thinking. What we call object-orientation today is really class-orientation, since functionality is spread throughout classes, instead of contained in Roles which interact at runtime. When you use DCI to separate Data (RoleObjectContracts) from Function (RoleMethods), you get a beautiful system architecture as a result. No polymorphism, no intergalactic GOTOs (aka virtual methods), everything is kept where it should be, in Context!

## Functionality and RoleMethods

Functionality can change frequently, as requirements changes. The Data however will probably remain stable much longer. An `Account` will stay the same, no matter how fancy web functionality is available. So take care when designing your Data classes. A well-defined Data structure can support a lot of functionality, by playing Roles in Contexts.

When designing functionality using RoleMethods in a Context, be careful not to end up with one big method doing all the work. That is an imperative approach which limits the power of DCI, since we're aiming for communication between Roles, not a procedural algorithm that tells the Roles what to do. Make the methods small, and let the mental model of the Context become the guideline. A [Use case](http://www.usability.gov/how-to-and-tools/methods/use-cases.html) is a formalization of a mental model that is supposed to map to a Context in DCI.

> A difference between [the imperative] kind of procedure orientation and object orientation is that in the former, we ask: _"What happens?"_ In the latter, we ask: _"Who does what?"_ Even in a simple example, a reader looses the "who" and thereby important locality context that is essential for building a mental model of the algorithm. ([From the DCI FAQ](http://fulloo.info/doku.php?id=what_is_the_advantage_of_distributing_the_interaction_algorithm_in_the_rolemethods_as_suggested_by_dci_instead_of_centralizing_it_in_a_context_method))

## A silver bullet?

Of course the answer is No, DCI isn't suitable for every problem. DCI is an approach to design that builds on a psychological model of the left-brain/right-brain dichotomy. It is just one model, though a very useful one when working close to users and their needs, especially where the discussions end up in a formalized use case.

Some cases don’t lend themselves very well to use cases but are better modeled by state machines, formal logic and rules, or database tables and transaction semantics. Or just simple, atomic MVC. Chances are though, if you're working with users, domain experts, stakeholders, etc, you'll notice them thinking in Roles, and if you let them do that instead of forcing a class-oriented mental model upon them, they will be happier, and DCI will be a great help!

# Larger examples and demos

- The [haxedci-example](https://github.com/ciscoheat/haxedci-example) repository has a larger example and demo that really showcases the power of DCI and MVC together. Check it out!
- [SnakeDCI](https://github.com/ciscoheat/SnakeDCI) is a recreation of the classic Snake game, to show you how DCI works in combination with a game framework.

# Technical notes

Because of the syntax, there are some problems with autocompletion for Roles. When inside a Role, RoleMethods below the current one may not show up.

# DCI Resources

## Videos 

['A Glimpse of Trygve: From Class-oriented Programming to Real OO' - Jim Coplien [ ACCU 2016 ]](https://www.youtube.com/watch?v=lQQ_CahFVzw)

[DCI – How to get ahead in system architecture](http://www.silexlabs.org/wwx2014-speech-andreas-soderlund-dci-how-to-get-ahead-in-system-architecture/)

## Links

Website - [fulloo.info](http://fulloo.info) <br>
FAQ - [DCI FAQ](http://fulloo.info/doku.php?id=faq) <br>
Support - [stackoverflow](http://stackoverflow.com/questions/tagged/dci), tagging the question with **dci** <br>
Discussions - [Object-composition](https://groups.google.com/forum/?fromgroups#!forum/object-composition) <br>
Wikipedia - [DCI entry](http://en.wikipedia.org/wiki/Data,_Context,_and_Interaction)

[![Build Status](https://travis-ci.org/ciscoheat/haxedci.svg?branch=master)](https://travis-ci.org/ciscoheat/haxedci)
