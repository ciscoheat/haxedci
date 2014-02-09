package dci;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
import haxe.ds.GenericStack.GenericStack;

// Data structure for storing all RoleMethod calls.
// {'$role.$method' => [RoleMethod, ...]
typedef RoleMethods = Map<String, RoleMethod>;

private class RoleMethod
{
	public var role : String;
	public var name : String;	
	public var calls(default, null) : Array<RoleMethod>;
	
	public function new(role, name)
	{
		this.role = role;
		this.name = name;
		this.calls = [];
	}
	
	public function addCall(call : RoleMethod)
	{
		calls.push(call);
	}
	
	public function toString()
	{
		return role + "." + name;
	}
}

/**
 * For generating graphs based on RoleMethod calls in a Context.
 */
class DiagramGenerator
{
	public var title(default, default) : String;
	
	var roleMethods : RoleMethods;
	
	// Starting points. A list of methods in the Context that will call RoleMethods.
	var interactions : Array<RoleMethod>;

	static var contextKey = "Context";

	public function new(?title : String) 
	{
		this.title = title;
		this.roleMethods = new RoleMethods();
		this.interactions = new Array<RoleMethod>();
	}
	
	private static function key(role : String, method : String)
	{
		return role + "." + method;
	}
	
	public function addInteraction(name : String, role : String, method : String)
	{	
		interactions.push(addRoleMethodCall(contextKey, name, role, method));
	}

	public function addRoleMethodCall(fromRole : String, fromMethod : String, toRole : String, toMethod : String)
	{
		var from = key(fromRole, fromMethod);
		var to = key(toRole, toMethod);
		
		if (!roleMethods.exists(from)) 
			roleMethods.set(from, new RoleMethod(fromRole, fromMethod));
		
		if (!roleMethods.exists(to))
			roleMethods.set(to, new RoleMethod(toRole, toMethod));
		
		roleMethods[from].addCall(roleMethods[to]);
		return roleMethods[from];
	}

	/**
	 * Generates code for a sequence diagram that can be used with http://www.websequencediagrams.com/
	 */
	public function generateSequenceDiagram()
	{
		FileSystem.createDirectory("./bin");
		FileSystem.createDirectory("./bin/dcigraphs");
		var file = File.write("./bin/dcigraphs/" + title + ".htm", false);

		var builder = new StringBuf();
		var lastCallMatch = ~/: \S/;
		
		builder.add("title " + title + "\n\n");
		
		for (method in interactions)
		{
			var interactBuilder = new StringBuf();
			var stack = new GenericStack<RoleMethod>();
			var active = new Map<String, Bool>();
			
			interactBuilder.add("alt " + method.name + "\n");
			
			recurseRoleMethod(method, stack, active, interactBuilder);
			
			var output = interactBuilder.toString().split("\n");
			var i = output.length;

			// Remove up to the last actual method call
			while(--i >= 0)
			{
				if (lastCallMatch.match(output[i]))
				{
					// When a RoleMethod call is found, go forward, keeping all deactivation commands.
					while (output[++i].indexOf("deactivate") == 0)
					{}
						
					break;
				}
			}
			
			output = output.slice(0, i);
			builder.add(output.join("\n") + "\nend\n\n");
		}
		
		file.writeString('<!DOCTYPE html>\n<html><head><title>$title</title></head><body><div class=wsd wsd_style="roundgreen"><pre>\n');
		file.writeString(builder.toString());
		file.writeString("</pre></div><script src='http://www.websequencediagrams.com/service.js'></script></body></html>");
		file.close();
	}
	
	private function recurseRoleMethod(current : RoleMethod, stack : GenericStack<RoleMethod>, activeRoles : Map<String, Bool>, builder : StringBuf)
	{
		var parent = stack.first();
		stack.add(current);
		
		var callSelf = parent != null && parent.role == current.role;
		var isLastCall = parent == null;
		
		if (parent != null)
		{
			isLastCall = parent.calls[parent.calls.length - 1] == current;

			var arrow = isLastCall ? "->" : "->>";			
			builder.add(parent.role + arrow + current.role + ": " + current.name + "\n");
			
			if (!callSelf)
			{
				if (isLastCall && parent.role != contextKey)
				{
					builder.add("deactivate " + parent.role + "\n");
					activeRoles.set(parent.role, false);
				}

				if (current.role != contextKey && !activeRoles.get(current.role) == true)
				{
					builder.add("activate " + current.role + "\n");
					activeRoles.set(current.role, true);
				}
			}
		}
	
		var last = current.calls.length - 1;
		for (method in current.calls)
		{
			recurseRoleMethod(method, stack, activeRoles, builder);
		}
		
		if (parent != null && !callSelf)
		{
			if (parent.role != contextKey)
			{
				builder.add(current.role + "-->>" + parent.role + ":\n");
				
				if (activeRoles.get(parent.role) != true)
				{
					builder.add("activate " + parent.role + "\n");
					activeRoles.set(parent.role, true);
				}
			}
			
			if (current.role != contextKey && activeRoles.get(current.role) == true)
			{
				builder.add("deactivate " + current.role + "\n");
				activeRoles.set(current.role, false);
			}
		}
		
		stack.pop();
	}
}