package haxedci;

import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using Lambda;

class Role
{
	public static var SELF = "self";	
	public static var CONTEXT = "context";

	public static function roleMethodFieldName(roleName : String, roleMethod : String)
	{
		return roleName + "__" + roleMethod;
	}
	
	public function new(field : Field) {
		if (field == null) throw "Null field.";
		
		this.field = field;
		this.bound = null;
		this.roleMethods = get_roleMethods();
	}
	
	public var field(default, null) : Field;
	public var bound(default, default) : Position;

	public var name(get, null) : String;
	function get_name() return field.name;

	public var roleMethods(default, null) : Map<String, RoleMethod>;
	function get_roleMethods() {
		var output = new Map<String, RoleMethod>();
		switch(field.kind) {
			case FVar(t, e): 
				if (t == null)
					Context.error("A Role var must have a Type as RoleInterface.", field.pos);
				if(e != null) switch e.expr {
					case EBlock(exprs): for(e in exprs) switch e.expr {
						case EFunction(name, f):
							if (name == null) Context.error("A RoleMethod must have a name.", e.pos);
							output.set(name, new RoleMethod(this, name, f));
						case _:
							Context.error("A Role can only contain simple functions as RoleMethods.", e.pos);
					}
					case _: 
						Context.error("A Role can only be assigned a block of RoleMethods.", e.pos);
				}
			case _:
				Context.error("Only var fields can be a Role.", field.pos);
		};
		return output;
	}

	function roleMethods_addSelf(rm : RoleMethod)
	{
		var f = rm.func;
		var roleName = this.name;
		switch(f.expr.expr)
		{
			case EBlock(exprs):
				exprs.unshift(macro var $SELF = this.$roleName);
				exprs.unshift(macro var $CONTEXT = this);
			case _:
				f.expr = {expr: EBlock([f.expr]), pos: f.expr.pos};
				roleMethods_addSelf(rm);
		}
	}
}
