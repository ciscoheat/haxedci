package haxedci;
import haxe.macro.Type;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
using Lambda;
using haxe.macro.MacroStringTools;
using haxe.macro.ComplexTypeTools;

class RoleObjectContractTypeMerger
{
	//static var typeCache = new Map<String, Type>();
	
	var type : ComplexType;
	var field : Field;
	var role : Role;

	public function new(role : Role) {
		this.role = role;
		this.field = role.field;
		
		switch(field.kind) {
			case FVar(t, _): this.type = t;
			case _: Context.error("Only var fields can be a Role.", field.pos);
		}
	}
	
	public function mergedType() : ComplexType {
		return field_mergeWithRole();
	}
	
	function field_mergeWithRole() : ComplexType {
		trace('----- Merging field and RoleObjectContract "${field.name}"');
		
		switch(type) {
			case TAnonymous(fields):
				trace("TAnonymous, merge with RoleObjectContract.");
				return mergeAnonymousInterfaces(fields);

			case TPath(p):
				trace('TPath: ' + p.pack.toDotPath(p.name));
				//if (typePath == "Array") return mergeTypeAndRoleObjectContract(null, p);
				
				/*
				if (!typeCache.exists(typePath)) {
					try {
						typeCache.set(typePath, Context.getType(typePath));
					} catch (e : Dynamic) {
						Context.error(e, Context.currentPos());
					}
				}
				
				var realType = typeCache.get(typePath);
				*/
				var realType = type.toType();
				return mergeTypeAndRoleObjectContract(realType, p);

			case _:
				Context.error("RoleObjectContracts must be defined as a Type or with class notation according to http://haxe.org/manual/struct#class-notation", field.pos);
				return null;
		}
	}
	
	// Special trick for autocompletion: At runtime, only objects that fulfill the RoleObjectContract
	// should be bound to a Role. When compiling however, it is convenient to also have the RoleMethods
	// displayed. Therefore, test if we're in autocomplete mode, add the RoleMethods if so.
	function mergeTypeAndRoleObjectContract(type : Type, typePath : TypePath) : ComplexType {		
		// Can only extend classes and structures, so test if type is one of those.
		if(type != null) switch(type) {
			case TMono(_), TLazy(_), TFun(_, _), TEnum(_, _), TDynamic(_):
				trace("Not a class or structure, using RoleObjectContract only.");
				return TAnonymous(role_methodList());
			case TAbstract(t, _):
				if (t.get().impl == null) {
					trace("Abstract type without implementation, using RoleObjectContract only.");
					return TAnonymous(role_methodList());
				}
				/*
				var impl = t.get().impl.get();
				var implPath = impl.pack.join('.') + (impl.pack.length > 0 ? '.' : '') + impl.name;
				trace("Found abstract type that implements " + implPath + ", trying new merge.");
				var underlyingType = Context.getType(implPath);
				return mergeTypeAndRoleObjectContract(underlyingType, {
					// TODO: Get sub from DefType?
					sub: null,
					params: impl.params.map(function(param) 
						return TPType(Context.toComplexType(param.t))
					),
					pack: impl.pack,
					name: impl.name
				});
				*/
			case TType(t, _):
				return mergeTypeAndRoleObjectContract(Context.follow(t.get().type), typePath);
				/*
				var underlying = t.get();
				trace("Found underlying type " + underlying.type + ", trying new merge.");
				return mergeTypeAndRoleObjectContract(underlying.type, {
					// TODO: Get sub from DefType?
					sub: null,
					params: underlying.params.map(function(param) 
						return TPType(Context.toComplexType(param.t))
					),
					pack: underlying.pack,
					name: underlying.name
				});
				*/
			case _:
		}
		
		var roleMethods = role_methodList();
		//Dci.fileTrace("Extending " + typePath.name + " with RoleObjectContract " + roleMethods.map(function(f) return f.name));
		// Creates a compile error if RoleObjectContract field exists on the type, 
		// which is useful since it's not allowed.
		if (roleMethods.length == 0) return TPath(typePath);
		#if (haxe_ver >= 3.1)
		return TExtend([typePath], roleMethods);
		#else
		return TExtend(typePath, roleMethods);
		#end		
	}

	// Same trick here as above.
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

		return TAnonymous(fields.concat(role_methodList()));
	}

	function role_methodList() : Array<Field> {
		var output = new Array<Field>();

		for (roleName in role.roleMethods.keys()) {
			var f = role.roleMethods.get(roleName);
			// TODO: Use some Context method to get the type?
			if (f.ret != null) {
				// There cannot be a body for the function because we're only creating 
				// a field definition, so a new definition needs to be created.
				output.push({
					kind: FFun({
						ret: f.ret,
						params: f.params,
						expr: null,
						args: f.args						
					}),
					name: roleName,
					access: [],
					pos: f.expr.pos,
					meta: [],
					doc: null
				});
			}
		}
		return output;
	}
}
#end
