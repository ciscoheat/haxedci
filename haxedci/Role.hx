package haxedci;

import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using Lambda;

class Role
{
	public function new(field : Field) {
		if (field == null) throw "field cannot be null.";
		
		this.field = field;
		this.bound = null;
		this.roleMethods = get_roleMethods();
	}
	
	public var field(default, null) : Field;
	public var bound(default, default) : Null<Position>;

	public var name(get, null) : String;
	function get_name() return field.name;

	public var roleMethods(default, null) : Map<String, RoleMethod>;
	function get_roleMethods() {
		var output = new Map<String, RoleMethod>();
		switch(field.kind) {
			case FVar(t, e): 
				if (t == null)
					Context.error("A Role var must have a Type as RoleObjectContract.", field.pos);
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
}
