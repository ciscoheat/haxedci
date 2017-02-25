package haxedci;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;

class DciContextBuilder
{
	public static function build() : Array<Field> {
		#if (haxe_ver < 3.4)
		throw "haxedci requires Haxe 3.4+";
		#end
		var context = new DciContext(Context.getLocalClass().get(), Context.getBuildFields());

		// Rewrite RoleMethod calls (destination.deposit -> destination__deposit)
		new haxedci.RoleMethodReplacer(context).replaceAll();
		
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
