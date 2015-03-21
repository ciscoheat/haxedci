package haxedci;

import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using Lambda;

class RoleMethod
{
	public var name(get, null) : String;
	function get_name() return signature.name;
	
	public var func : Function;
	public var signature : Field;
	
	public function new(name : String, func : Function) {
		this.func = func;
		this.signature = {
			kind: FFun({
				ret: func.ret,
				params: func.params,
				expr: null,
				args: func.args
			}),
			name: name,
			access: [],
			pos: func.expr.pos,
			meta: [],
			doc: null
		};
	}
}

class Role
{
	public static var CONTEXT = "context";
	public static var SELF = "self";

	public static function roleMethodFieldName(roleName : String, roleMethod : String)
	{
		return roleName + "__" + roleMethod;
	}

	public static function isRoleField(field : Field) {
		if (!field.meta.exists(function(m) return m.name == "role")) return false;
		var error = function() {
			Context.error("@role can only be used on non-static var fields.", field.pos);
			return false;
		}
		
		switch(field.kind) {
			case FVar(_, _): 
				return field.access.has(AStatic) ? error() : true;
			case _:
				return error();
		}
	}
	
	public function new(field : Field) {
		if (field == null) throw "Null field.";
		
		this.field = field;
		this.bound = null;
		this.roleMethods = get_roleMethods();
	}
	
	public function addFields(fields : Array<Field>) {
		// Remove expr from field, not needed anymore when roleMethods are extracted
		// And for convenience, because now it can simply be added in addFields()
		switch(field.kind) {
			case FVar(t, e):
				field.kind = Context.defined("display") 
					? FVar(new RoleObjectContractTypeMerger(this).mergedType(), null)
					: FVar(t, null);
			case _:
				Context.error("Only var fields can be a Role.", field.pos);
		}
		
		fields.push(field);

		// Add the RoleMethods
		for (rmName in roleMethods.keys()) {
			var rm = roleMethods.get(rmName);
			var field = {
				pos: rm.func.expr.pos,
				name: roleMethodFieldName(this.name, rmName),
				meta: [{ pos: rm.func.expr.pos, params: [], name: ":noCompletion" }],
				kind: FFun(rm.func),
				doc: null,
				access: [APrivate]
			};

			// Add "self" and "context" to roleMethods, and set a type.
			roleMethods_addSelf(rm);			

			#if debug
			if (rm.func.ret == null && Context.defined("dci-signatures-warnings")) {
				Context.warning("RoleMethod without explicit return value", rm.func.expr.pos);
			}
			#end
			
			fields.push(field);
		}
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
							output.set(name, new RoleMethod(name, f));
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
