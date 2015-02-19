package haxedci;

#if macro
import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.Context;

using Lambda;
using haxe.macro.MacroStringTools;
using haxe.macro.ComplexTypeTools;

class RoleObjectContractTypeMerger
{
	var type : ComplexType;
	var role : Role;

	public function new(role : Role) {
		this.role = role;
		
		switch(role.field.kind) {
			case FVar(t, _): this.type = t;
			case _: Context.error("Only var fields can be a Role.", role.field.pos);
		}
	}
	
	public function mergedType() : ComplexType {
		return type_mergeWithRole();
	}
	
	function type_mergeWithRole() : ComplexType {
		//trace('----- Merging type and RoleObjectContract "${role.field.name}"');
		
		switch(type) {
			case TAnonymous(fields):
				//trace("TAnonymous, merge with RoleObjectContract.");
				return mergeAnonymousInterfaces(fields);

			case TPath(p):
				//trace('TPath: ' + p.pack.toDotPath(p.name));
				return mergeTypeAndRoleObjectContract(type.toType(), p);

			case _:
				Context.error("RoleObjectContracts must be defined as a Type or with class notation according to http://haxe.org/manual/struct#class-notation", role.field.pos);
				return null;
		}
	}
	
	function mergeTypeAndRoleObjectContract(type : Type, typePath : TypePath) : ComplexType {		
		// Can only extend classes and structures, so test if type is one of those.
		if(type != null) switch(type) {
			case TMono(_), TLazy(_), TFun(_, _), TEnum(_, _), TDynamic(_):
				//trace("Not a class or structure, using RoleObjectContract only.");
				return TAnonymous(role_typeDef());
			case TAbstract(t, _):
				if (t.get().impl == null) {
					//trace("Abstract type without implementation, using RoleObjectContract only.");
					return TAnonymous(role_typeDef());
				}
				// TODO: Test if recursion with the underlying type is needed (or follow)
			case TType(t, _):
				return mergeTypeAndRoleObjectContract(Context.follow(t.get().type), typePath);
			case _:
		}
		
		var roleMethods = role_typeDef();
		if (roleMethods.length == 0) return TPath(typePath);
		
		// Creates a compile error if RoleObjectContract field exists on the type, 
		// which is useful since it's not allowed.
		#if (haxe_ver >= 3.1)
		return TExtend([typePath], roleMethods);
		#else
		return TExtend(typePath, roleMethods);
		#end		
	}

	function mergeAnonymousInterfaces(fields : Array<Field>) : ComplexType {
		// Test if there are RoleObjectContract/Method name collisions
		var hash = new Map<String, Field>();
		for (field in fields) hash[field.name] = field;

		for (method in role.roleMethods.keys())
		{
			if (hash.exists(method)) {
				Context.error('The RoleObjectContract field "' + hash[method].name + 
				'" has the same name as a RoleMethod.', hash[method].pos);
			}
		}

		return TAnonymous(fields.concat(role_typeDef()));
	}

	function role_typeDef() : Array<Field> {
		// TODO: Move rmSignatures to a better place
		return Dci.rmSignatures.get(role.context.name + '-' + role.name);
	}
}
#end
