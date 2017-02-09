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
	public static var allowThisInRoleMethods = false;
	public static var publicRoleAccess = false;
	
	public static function build() : Array<Field> {
		var context = new DciContext(Context.getLocalClass().get(), Context.getBuildFields());

		/*
		trace('===== Context ' + cls.name + ' =================');
		trace('Fields: ' + context.fields.map(function(f) return f.name));
		for (role in context.roles) {
			trace('Role: ' + role.name + ' ' + role.contract.map(function(r) return r.name));
			trace("\\-- " + role.roleMethods.map(function(rm) return rm.name));
		}
		*/
		
		// Rewrite RoleMethod calls (destination.deposit -> destination__desposit)
		new RoleMethodReplacer(context).replaceAll();
		
		if (!Context.defined("display")) {
			// After all replacement is done, test if all roles are bound.
			for (r in context.roles) if(r.bound == null) {
				Context.warning("Role " + r.name + " isn't bound in its Context.", r.field.pos);
			}
		} else {
			//Autocompletion.fileTrace(contextData(context));
		}

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
