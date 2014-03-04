package haxedci;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxedci.DiagramGenerator.RoleMethods;
using haxe.macro.ExprTools;

private class Role
{
	// RoleMethod name -> Field (field.name is rewritten so it cannot be used directly)
	public var methods : Map<String, Field>;
	
	public var field : Field;
	public var bound : Position;
		
	public function new(field : Field)
	{
		if (field == null) throw "Null field: " + field;
		
		this.field = field;
		this.methods = new Map<String, Field>();
	}
}

private typedef Roles = Map<String, Role>;

class Dci
{
	@macro public static function context() : Array<Field>
	{
		return new Dci().execute();
	}

	static var CONTEXT = "context";
	static var SELF = "self";
	static var ROLEINTERFACE = "roleInterface";
	
	var roles : Roles;
	
	public function new()
	{
		roles = new Roles();		
	}
	
	public function execute() : Array<Field>
	{	
		var fields = Context.getBuildFields();
		var outputFields : Array<Field> = [];
		var diagram : DiagramGenerator;

		//trace("======================== Context: " + Context.getLocalClass());

		for (field in fields)
		{
			if (hasRole(field))
				addRole(field);				
			else
				outputFields.push(field);
		}
		
		#if dcigraphs
		if(!Context.defined("display"))
			diagram = new DiagramGenerator(Context.getLocalClass().toString());
		#end
		
		// Replace function calls with Role method calls, where appropriate
		for (field in fields)
		{
			var isRole = hasRole(field);
			
			var ex : Expr;
			var functionName : String = null;
			var functionRef : Function = null;
			
			switch(field.kind)
			{
				case FVar(_, e): 
					ex = e;
				case FFun(f): 
					ex = f.expr;
					functionName = field.name;
					functionRef = f;
				case FProp(_, _, _, e): 
					ex = e;
			}
			
			if (ex != null)
			{
				//trace("----- Field: " + field.name);
				ex.iter(function(e) { replaceRoleMethodCalls(e, isRole ? field.name : null, functionName, functionRef, diagram); } );
			}				
		}
		
		// Test if all roles were bound.
		for (roleName in roles.keys())
		{
			if (roles.get(roleName).bound == null)
				Context.warning("Role " + roleName + " isn't bound in this Context.", roles.get(roleName).field.pos);
		}
		
		#if dcigraphs
		if (!Context.defined("display") && diagram != null)
		{
			diagram.generateSequenceDiagrams();
			diagram.generateDependencyGraphs();
		}
		#end
		
		for (roleName in roles.keys())
		{
			if (roles.get(roleName).methods == null) continue;

			for (roleMethod in roles.get(roleName).methods)
			{
				switch(roleMethod.kind)
				{
					case FFun(f):
						addSelfToMethod(f, roleName);
						
					case _:						
						Context.error('Incorrect RoleMethod definition.', roleMethod.pos);
				}				
			}
		}
		
		for (role in roles)
		{
			// Could fix possible autocompletion problem:
			//if (role.methods == null) continue;
			
			outputFields.push(role.field);
			
			for (method in role.methods)
				outputFields.push(method);
		}
		
		return outputFields;
	}

	static function hasRole(field : Field)
	{
		return Lambda.exists(field.meta, function(m) { return m.name == "role"; } );
	}
	
	// Replace Role method calls with the transformed version.
	// If roleName is null, we're not in a RoleMethod.
	// If methodName is null, we're not in a method (rather a var or property)
	var lastRoleRef : Expr;
	var roleBindMethod : Function;
	function replaceRoleMethodCalls(e : Expr, roleName : String, methodName : String, methodRef : Function, generator : DiagramGenerator)
	{
		if (Context.defined("display")) return;
		
		switch(e.expr)
		{
			case EBinop(op, e1, e2):
				switch(op)
				{
					case OpAssign:
						var fieldArray = extractField(e1, roleName);
						if (fieldArray != null)
						{
							if (fieldArray[0] == "this") fieldArray.shift();
							
							if (fieldArray.length == 1 && roles.exists(fieldArray[0]))
							{
								// Set where the Role was bound in the Context.
								roles.get(fieldArray[0]).bound = e.pos;
								
								//haxe.macro.Context.warning("Binding role " + fieldArray[0] + " in " + methodName, e.pos);

								if (roleBindMethod == null)
								{
									roleBindMethod = methodRef;
								}
								else if (roleBindMethod != methodRef)
								{
									Context.warning('Last Role assignment outside current method', lastRoleRef.pos);
									Context.error('All Roles in a Context must be assigned in the same method.', e.pos);
								}
								
								lastRoleRef = e;
							}
						}
						
					case _:
				}
			
			case EFunction(name, f):
				// Note that anonymous functions will have name == null, then keep previous name.
				var mName = name != null ? name : methodName;
				//if(name != null) trace("- Function: " + roleName + "." + mName);
				replaceRoleMethodCalls(f.expr, roleName, mName, methodRef, generator);
				return;
			
			case EField(e3, fd):
				var fieldArray = extractField(e, roleName);
				if (fieldArray != null)
				{
					// Rewriting [this, console, newline] to [this, console_newline]
					//trace(fieldArray);
					
					var newArray = [];
					var skip = false;
					var length = fieldArray.length;
					
					for (i in 0...length)
					{
						if (skip)
						{
							skip = false;
							continue;
						}
						
						// Test if we're past the end of array (no need to check last field),
						// or if a Role is matching the field.
						var field = fieldArray[i];
						
						if (generator != null && roles.exists(field))
						{
							if (roleName != null)
							{
								generator.addDependency(roleName, field);
							}
							else if(i < length-1 && roles.get(field).methods.exists(fieldArray[i+1]))
							{
								generator.addDependency(roleName, field);					
							}
						}
						
						if (i > length-2 || !roles.exists(field) || roles.get(field).methods == null || !roles.get(field).methods.exists(fieldArray[i+1]))
						{
							newArray.push(field);
						}
						else					
						{							
							var roleMethod = roleMethodName(field, fieldArray[i + 1]);
							newArray.push(roleMethod);
							skip = true; // Skip next field since it's now a part of the Role method call.

							//trace("RoleMethod call: " + roleMethod + " at " + e3.pos);
							//trace(roleName, methodName, field, fieldArray[i + 1]);

							// Add diagram generation data
							if (generator != null)
							{								
								if (roleName == null && methodName != null)
								{
									generator.addInteraction(methodName, field, fieldArray[i + 1]);
								}
								else if (roleName != null && methodName != null)
								{
									generator.addRoleMethodCall(roleName, methodName, field, fieldArray[i + 1]);
								}
							}
						}
					}
					
					if (fieldArray.length != newArray.length)
					{
						e.expr = buildField(newArray, newArray.length - 1, e3.pos);						
						return;
					}					
				}
				
			case _: 
		}
		
		e.iter(function(e) { replaceRoleMethodCalls(e, roleName, methodName, methodRef, generator); });
	}

	// Extract the field to an array. this.test.length = ['this', 'test', 'length']
	// Also replace "self" with the roleName if set.
	static function extractField(e : Expr, roleName : String)
	{
		var output = [];
		while (true)
		{
			switch(e.expr)
			{
				case EField(e2, field):
					var replace = (roleName != null && field == SELF) ? roleName : field;
					output.unshift(replace);
					e = e2;
				
				case EConst(c):
					switch(c)
					{
						case CIdent(s):
							var replace = (roleName != null && s == SELF) ? roleName : s;
							output.unshift(replace);
							//trace(output);
							return output;
							
						case _:
							return null;
					}
					
				case _:
					return null;
			}
		}
	}
	
	// The reverse of extractField.
	static function buildField(identifiers, i, pos)
	{
		if (i > 0)
			return EField({expr: buildField(identifiers, i - 1, pos), pos: pos}, identifiers[i]);
		else
			return EConst(CIdent(identifiers[i]));
	}
	
	// Special trick for autocompletion: At runtime, only objects that fulfill the RoleInterface
	// should be bound to a Role. When compiling however, it is convenient to also have the RoleMethods
	// displayed. Therefore, test if we're in autocomplete mode, add the RoleMethods if so.
	function mergeTypeAndRoleInterface(role : Role, type : TypePath) : ComplexType
	{
		if (Context.defined("display"))
		{
			// Can only extend classes and structures, so test if type is one of those.
			var realType = haxe.macro.Context.getType(type.name);
			if (realType == null) return TPath(type);
			switch(realType)
			{
				case TMono(_), TLazy(_), TFun(_, _), TEnum(_, _), TDynamic(_), TAbstract(_, _):
					return TAnonymous(roleMethodsList(role));
				case _:
			}
			// Creates a compile error if RoleInterface field exists on the type, which is useful.			
			
			// TExtend changed in 3.1, need this fix when haxe_ver works (gives same value for 3.0.1 right now)
			#if (haxe_ver >= 3.01)
			return TExtend(type, roleMethodsList(role));
			#else
			return TExtend(type, roleMethodsList(role));
			#end
		}

		return TPath(type);
	}

	// Same trick here as above.
	function mergeAnonymousInterfaces(role : Role, fields : Array<Field>) : ComplexType
	{
		if (Context.defined("display"))
		{
			// Test if there are RoleInterface/Method name collisions
			var hash = new Map<String, Field>();
			for (field in fields) hash[field.name] = field;
					
			for (method in role.methods.keys())
			{
				if (hash.exists(method))
					Context.error('The RoleInterface field "' + hash[method].name + '" has the same name as a RoleMethod.', hash[method].pos);
			}
				
			return TAnonymous(fields.concat(roleMethodsList(role)));
		}

		return TAnonymous(fields);
	}
	
	function roleMethodsList(role : Role) : Array<Field>
	{
		var output = new Array<Field>();
		
		for (roleName in role.methods.keys())
		{
			var m = role.methods.get(roleName);
			switch(m.kind)
			{
				case FFun(f):
					if (f.ret != null)
					{
						// There cannot be a body for the function because we're only creating a field definition,
						// so a new definition needs to be created.
						var functionDef = {
							ret: f.ret,
							params: f.params,
							expr: null,
							args: f.args
						}
						
						output.push(contextField(FFun(functionDef), roleName, [], f.expr.pos));
					}
				case _:
					Context.error("Incorrect RoleMethod definition: Must be a function.", m.pos);
			}
		}
		return output;
	}
	
	// Add a Role object to roles.
	function addRole(field : Field)
	{
		if (field.name == SELF)
			Context.error('A Role cannot be named "$SELF", it is used as an accessor within RoleMethods.', field.pos);
		else if (field.name == "Context") // Reserved for diagrams.
			Context.error('A Role cannot be named "Context".', field.pos);
			
		var error = function(p) { Context.error("Incorrect Role definition: Must be a var.", p); };		
		var role = new Role(contextField(null, field.name, [APrivate], field.pos));
		
		switch(field.kind)
		{
			case FVar(t, e): 
				if (t != null)
				{
					// Add a simple role definition, like: 
					// @role static var amount : Float
					switch(t)
					{
						case TPath(p): 
							//trace("Adding Role " + field.name + " with only a type");
							role.field.kind = FVar(mergeTypeAndRoleInterface(role, p));
						case _: error(field.pos);
					}
				}
				else
				{					
					switch(e.expr)
					{
						// The Role is defined using a block.
						case EBlock(exprs):
							
							// First, find and extract the RoleMethods
							for (expr in exprs)
							{
								switch(expr.expr)
								{
									case EFunction(name, f): 
										//trace("Adding RoleMethod " + name + " for Role " + field.name);
										var methodName = roleMethodName(field.name, name);
										var noCompletion = { pos: f.expr.pos, params: [], name: ":noCompletion" };
										var roleField = contextField(FFun(f), methodName, [APrivate], f.expr.pos, [noCompletion]);
										
										if(role.methods != null)
											role.methods.set(name, roleField);
										
										//if(f.ret == null)
										//	haxe.macro.Context.warning("The RoleMethod " + field.name + "." + name + " has no return type, add it if you need autocompletion.", expr.pos);
											
									case _:
								}
							}
							
							var found = false;
							
							// Then create the Role with its RoleInterface based on the RoleMethods.
							for (expr in exprs)
							{
								switch(expr.expr)
								{
									case EVars(vars):
										for (v in vars)
										{
											if (v.name == ROLEINTERFACE)
											{
												switch(v.type)
												{
													case TAnonymous(fields):
														//trace("Adding Role " + field.name + " with RoleInterface");
														role.field.kind = FVar(mergeAnonymousInterfaces(role, fields));
														found = true;
														
													case TPath(p):
														//trace("Adding Role " + field.name + " with Type as RoleInterface: " + p);
														role.field.kind = FVar(mergeTypeAndRoleInterface(role, p));
														found = true;
														
													case _: Context.error("RoleInterfaces must be defined as a Type or with class notation according to http://haxe.org/manual/struct#class-notation", expr.pos);
												}												
											}
											else
											{
												Context.error("The only variable that can exist in a Role definition must be named \"" + ROLEINTERFACE + "\".", expr.pos);
											}
										}
										
									case _:
								}
							}
							
							if (!found)
							{
								//trace("No RoleInterface found, adding Role '" + field.name + "' as Dynamic");
								role.field.kind = FVar(TPath({ name: 'Dynamic', pack: [], params: [] }));
							}
							
						case _: error(e.pos);
					}
				}
					
			case _: error(field.pos);
		}		
		
		// Some autocomplete problem forces this
		if (roles == null) roles = new Roles();
		
		roles.set(field.name, role);
	}
	
	private static function contextField(kind : FieldType, name : String, access : Array<Access>, pos : Position, meta : Array<MetadataEntry> = null) : Field
	{
		if (meta == null) meta = [];
		
		var output = {
			pos: pos,
			name: name,
			meta: meta,
			kind: kind,
			doc: null,
			access: access
		};
		
		return output;
	}
	
	private static function roleMethodName(role : String, method : String)
	{
		return role + "__" + method;
	}
	
	function addSelfToMethods(field : Field)
	{
		var errorMsg = "Incorrect RoleMethod definition: Must be a block or a Type.";
		var error = function(p) { Context.error(errorMsg, p); };
		
		switch(field.kind)
		{
			case FVar(t, e): 
				if (t != null) return;

				switch(e.expr)
				{
					case EBlock(exprs):
						for (expr in exprs)
						{
							switch(expr.expr)
							{
								case EFunction(name, f):
									addSelfToMethod(f, field.name);
									
								case _:
							}
						}
						
					case _: error(e.pos);
				}
					
			case _: error(field.pos);
		}		
	}
	
	function addSelfToMethod(f : Function, roleName : String)
	{
		switch(f.expr.expr)
		{
			case EBlock(exprs): 
				exprs.unshift(macro var $SELF = this.$roleName);
				exprs.unshift(macro var $CONTEXT = this);
			case _:
				f.expr = {expr: EBlock([f.expr]), pos: f.expr.pos};
				addSelfToMethod(f, roleName);
		}
	}
}
#end
