package haxedci;
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

private class DepNode
{
	public var name : String;
	public function new(name : String) this.name = name;
	
	public function toString()
	{
		return 'var $name = graph.newNode({label: "$name"});';
	}
}

private class DepNodeEdge
{
	public var from : String;
	public var to : String;
	public var color : String;
	
	public function new(from : String, to : String, color : String)
	{
		this.from = from;
		this.to = to;
		this.color = color;
	}
	
	public function toString()
	{
		return 'graph.newEdge($from, $to, {color: "$color"});';
	}
	
	public function equals(edge : DepNodeEdge)
	{
		return this.from == edge.from && this.to == edge.to;
	}
}

/**
 * For generating graphs based on RoleMethod calls in a Context.
 */
class DiagramGenerator
{
	public var title(default, default) : String;
	
	// Starting points. A list of methods in the Context that will call RoleMethods.
	var interactions : Array<RoleMethod>;
	var roleMethods : RoleMethods;	

	// Dep. graph data
	var nodes : Map<String, DepNode>;
	var edges : Array<DepNodeEdge>;
	
	static var contextKey = "Context";

	public function new(?title : String) 
	{
		this.title = title;
		this.roleMethods = new RoleMethods();
		this.interactions = new Array<RoleMethod>();
		
		this.nodes = new Map<String, DepNode>();
		this.edges = [];
	}
	
	private static function key(role : String, method : String)
	{
		return role + "." + method;
	}
	
	public function addDependency(from : String, to : String)
	{
		if (from == null) from = "Context";
		
		if (!nodes.exists(from))
		{
			nodes.set(from, new DepNode(from));
		}

		if (!nodes.exists(to))
		{
			nodes.set(to, new DepNode(to));
		}
		
		var newEdge = new DepNodeEdge(from, to, from == "Context" ? "#CC333F" : "#00A0B0");		
			
		if (!Lambda.exists(edges, function(e) { return e.equals(newEdge); } ))
		{
			edges.push(newEdge);
			//trace(newEdge);
		}
	}
	
	public function addInteraction(name : String, role : String, method : String)
	{
		var interaction = addRoleMethodCall(contextKey, name, role, method);
		//trace("Adding interaction: " + interaction);
		interactions.push(interaction);
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
		
		//trace("Adding RoleMethod call: " + roleMethods[from]);
		return roleMethods[from];
	}
	
	/**
	 * Generates code for dependency graphs using http://getspringy.com/
	 */
	public function generateDependencyGraphs()
	{
		FileSystem.createDirectory("./bin");
		FileSystem.createDirectory("./bin/dcigraphs");
		FileSystem.createDirectory("./bin/dcigraphs/dependency");
		
		var file = File.write("./bin/dcigraphs/dependency/" + title + ".htm", false);
		var builder = new StringBuf();
		
		builder.add('<!DOCTYPE html>
<html><head><title>$title</title></head><body><h1>$title</h1>
<script src="http://code.jquery.com/jquery-1.11.0.min.js"></script>
<script src="http://ciscoheat.github.io/cdn/js/springy-2.2.2.js"></script>
<script src="http://ciscoheat.github.io/cdn/js/jquery.springyui.js"></script>
<script>var graph = new Springy.Graph();
		');
		
		for (n in nodes) builder.add(n.toString());
		for (e in edges) builder.add(e.toString());
		
		builder.add('
jQuery(function(){ var springy = window.springy = jQuery("#springydemo").springy({graph: graph}); });
</script>
<canvas id="springydemo" width="1024" height="768"></canvas>
<p><a href="http://getspringy.com/">http://getspringy.com/</a></p>
</body>
</html>
		');
		
		file.writeString(builder.toString());
		file.close();
	}

	/**
	 * Generates code for a sequence diagram using http://www.websequencediagrams.com/
	 */
	public function generateSequenceDiagrams()
	{
		FileSystem.createDirectory("./bin");
		FileSystem.createDirectory("./bin/dcigraphs");
		FileSystem.createDirectory("./bin/dcigraphs/sequence");
		var file = File.write("./bin/dcigraphs/sequence/" + title + ".htm", false);

		var builder = new StringBuf();
		var lastCallMatch = ~/: \S/;
		var addedMethods = new Map<String, Bool>();
		
		builder.add('<!DOCTYPE html>\n<html><head><title>$title</title></head><body><div class=wsd wsd_style="roundgreen"><pre>\n');
		builder.add("title " + title + "\n\n");
		
		for (method in interactions)
		{
			if (addedMethods.exists(method.toString())) continue;
			
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
			
			addedMethods.set(method.toString(), true);
		}
		
		builder.add("</pre></div><script src='http://www.websequencediagrams.com/service.js'></script></body></html>");
		
		file.writeString(builder.toString());
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