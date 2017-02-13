package haxedci;
import haxe.ds.ObjectMap;

#if macro
import haxe.macro.Type.ClassType;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxedci.DciContext.DciRole;
import haxedci.DciContext.DciRoleMethod;
import haxedci.Autocompletion.fileTrace;

using Lambda;
using StringTools;
using haxe.macro.ExprTools;

class DciContextBuilder
{
	public static function build() : Array<Field> {
		#if (haxe_ver < 3.4)
		throw "haxedci requires Haxe 3.4+";
		#end
		var context = new DciContext(Context.getLocalClass().get(), Context.getBuildFields());

		// Rewrite RoleMethod calls (destination.deposit -> destination__deposit)
		new RoleMethodReplacer(context).replaceAll();
		
		return context.buildFields();
	}

	public static function contextData(context : DciContext) {
		return "===== " + context.name + "\n" +
		context.roles.map(function(role)
			return role.name + " " + 
			role.contract.map(function(c) return c.name) 
			+ role.roleMethods.map(function(rm) return rm.name)
		).join("\n");
	}
}
#end
