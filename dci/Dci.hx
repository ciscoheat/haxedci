package dci;
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;

#if macro
// A map for detecting role names. Role => [RoleMethod, ...]
private typedef RoleNameMap = Map<String, Array<String>>;

// A map for the RoleMethods, used when adding 'self'.
private typedef RoleMap = Map<String, Array<Function>>;

// A map for the types of the RoleMethod functions.
private typedef RoleInterfaceList = Map<String, Array<Field>>;

// The final RoleInterface type, an anonymous type with or without an extension.
private typedef RoleInterfaces = Map<String, ComplexType>;

class Dci
{
	@macro public static function context() : Array<Field>
	{
		return new Dci().execute();
	}

	private static var CONTEXT = "context";
	private static var SELF = "self";
	private static var ROLEINTERFACE = "roleInterface";

	var roleFields : Array<Field>;
	var roleIdentifiers : Map<String, Bool>;
	
	var nonRoleFields : Array<Field>;
	var roleMethodNames : RoleNameMap;
	var roleMethods : RoleMap;
	var roleInterfaceList : RoleInterfaceList;
	var roleInterfaces : RoleInterfaces;
	var roleBindMethod : Function;
	
	public function new()
	{
		roleFields = [];
		roleIdentifiers = new Map<String, Bool>();
		
		nonRoleFields = [];
		roleMethodNames = new RoleNameMap();
		roleMethods = new RoleMap();
		roleInterfaceList = new RoleInterfaceList();
		roleInterfaces = new RoleInterfaces();
	}
	
	public function execute() : Array<Field>
	{	
		var fields = Context.getBuildFields();

		//trace("=== Context: " + Context.getLocalClass());

		// First pass: Add Role methods and create the RoleInterfaces map.
		for (field in fields)
		{
			if (field.name == "testNoBlock") trace(field);
			
			addRoleMethods(field);
		}

		// Second pass: Add Roles.
		for (field in fields)
		{
			if(hasRole(field)) addRole(field);
		}
		
		#if dcigraphs
		var diagram = new DiagramGenerator(Context.getLocalClass().toString());
		#else
		var diagram = null;
		#end
		
		for (field in roleFields)
			roleIdentifiers.set(field.name, true);
		
		// Third pass: Replace function calls with Role method calls, where appropriate		
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
				ex.iter(function(e) { replaceRoleMethodCalls(e, isRole ? field.name : null, functionName, functionRef, diagram); } );
				
			if (!isRole)
				nonRoleFields.push(field);
		}
		
		#if dcigraphs
		diagram.generateSequenceDiagram();
		#end
		
		for (roleName in roleMethods.keys())
		{
			for (roleMethod in roleMethods[roleName])
			{
				addSelfToMethod(roleMethod, roleName);
			}
		}
		
		return roleFields.concat(nonRoleFields);
	}

	static function hasRole(field : Field)
	{
		return Lambda.exists(field.meta, function(m) { return m.name == "role"; } );
	}
	
	// Replace Role method calls with the transformed version.
	// If roleName is null, we're not in a RoleMethod.
	// If methodName is null, we're not in a method (rather a var or property)
	private var lastRoleRef : Expr;
	function replaceRoleMethodCalls(e : Expr, roleName : String, methodName : String, methodRef : Function, generator : DiagramGenerator)
	{
		switch(e.expr)
		{
			case EBinop(op, e1, e2):
				switch(op)
				{
					case OpAssign:
						var fieldArray = extractField(e1, roleName);
						if (fieldArray[0] == "this") fieldArray.shift();
						
						if (fieldArray.length == 1 && roleIdentifiers.exists(fieldArray[0]))
						{
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
						
					case _:
				}
			
			case EFunction(name, f):
				// Note that anonymous functions will have name == null, then keep previous name.
				replaceRoleMethodCalls(f.expr, roleName, name != null ? name : methodName, methodRef, generator);
				return;
			
			case EField(e3, fd):
				var fieldArray = extractField(e, roleName);
				if (fieldArray != null)
				{
					var newArray = [];
					var skip = false;
					var length = fieldArray.length;
					
					for (i in 0 ... length)
					{
						if (skip)
						{
							skip = false;
							continue;
						}
						
						// Test if we're past the end of array (no need to check last field),
						// or if a Role is matching the field.
						var field = fieldArray[i];
						if (i > length-2 || !roleMethodNames.exists(field) || !Lambda.has(roleMethodNames[field], fieldArray[i + 1]))
						{
							newArray.push(field);
							continue;
						}
						
						var roleMethod = roleMethodName(field, fieldArray[i + 1]);
						
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

						newArray.push(roleMethod);
						skip = true; // Skip next field since it's now a part of the Role method call.
					}
					
					if (fieldArray.length != newArray.length)
					{
						//trace("Role method call: " + newArray.join(".") + " at " + e.pos);
						e.expr = buildField(newArray, newArray.length - 1, e.pos);
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
	function mergeTypeAndRoleInterface(fieldName : String, type : TypePath) : ComplexType
	{
		if (Context.defined("display") && roleInterfaceList.exists(fieldName))
		{
			// Creates a compile error if RoleInterface field exists on the type, which is useful.
			return TExtend(type, roleInterfaceList[fieldName]);
		}

		return TPath(type);
	}

	// Same trick here as above.
	function mergeAnonymousInterfaces(fieldName : String, fields : Array<Field>) : ComplexType
	{
		if (Context.defined("display") && roleInterfaceList.exists(fieldName))
		{
			// Test if there are RoleInterface/Method name collisions
			var hash = new Map<String, Field>();
			for (field in fields) hash[field.name] = field;
					
			for (method in roleMethodNames[fieldName])
			{
				if (hash.exists(method))
					Context.error('The RoleInterface field "' + hash[method].name + '" has the same name as a RoleMethod.', hash[method].pos);
			}
				
			return TAnonymous(fields.concat(roleInterfaceList[fieldName]));
		}

		return TAnonymous(fields);
	}
	
	//function mergedRoleInterface(fieldName : String

	function addRole(field : Field)
	{
		if (field.name == SELF)
			Context.error('A Role cannot be named "$SELF", it is used as an accessor within RoleMethods.', field.pos);
		else if (field.name == "Context") // Reserved for sequence diagrams.
			Context.error('A Role cannot be named "Context".', field.pos);
			
		var error = function(p) { Context.error("Incorrect Role definition: Must be a var.", p); };
		
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
							var fieldType = mergeTypeAndRoleInterface(field.name, p);
							roleFields.push(contextField(FVar(fieldType), field.name, [APrivate], field.pos));
							roleInterfaces[field.name] = fieldType;
							return;
						case _: error(field.pos);
					}
				}
				else
				{
					var found = false;
					
					switch(e.expr)
					{
						// The role is defined using a block, so search for a RoleInterface.
						case EBlock(exprs):
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
														var fieldType = mergeAnonymousInterfaces(field.name, fields);
														roleFields.push(contextField(FVar(fieldType), field.name, [APrivate], expr.pos));
														roleInterfaces[field.name] = fieldType;
														found = true;
														
													case TPath(p):
														//trace("Adding Role: " + field.name + " with simple RoleInterface");
														var fieldType = mergeTypeAndRoleInterface(field.name, p);
														roleFields.push(contextField(FVar(fieldType), field.name, [APrivate], expr.pos));
														roleInterfaces[field.name] = fieldType;
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
								//trace("No RoleInterface found, adding Role " + field.name + " as Dynamic");
								roleFields.push(contextField(FVar(TPath( { name: 'Dynamic', pack: [], params: [] } ), null), field.name, [APrivate], e.pos));
							}
							
						case _: error(e.pos);
					}
				}
					
			case _: error(field.pos);
		}		
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
		var errorMsg = "Incorrect Role method definition: Must be a block or a Type.";
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
	
	function addRoleMethods(field : Field)
	{
		if (!hasRole(field)) return;
		
		var errorMsg = "Incorrect Role method definition: Must be a block or a Type.";
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
									var methodName = roleMethodName(field.name, name);
									var noCompletion = { pos: f.expr.pos, params: [], name: ":noCompletion" };
									//trace("Adding role method: " + methodName);
									roleFields.push(contextField(FFun(f), methodName, [APrivate], f.expr.pos, [noCompletion]));
																		
									// Store the RoleMethod for usage in next passes
									if (!roleMethodNames.exists(field.name))
									{
										roleMethodNames.set(field.name, []);
										roleMethods.set(field.name, []);
									}

									roleMethodNames[field.name].push(name);
									roleMethods[field.name].push(f);
									
									// Autocompletion can only display when the return type is known, 
									// so only define the RoleInterface if it is set.
									if (f.ret != null)
									{
										if (!roleInterfaceList.exists(field.name))
											roleInterfaceList.set(field.name, []);
										
										// There cannot be a body for the function because we're only creating a field definition,
										// so a new definition needs to be created.
										var functionDef = {
											ret: f.ret,
											params: f.params,
											expr: null,
											args: f.args
										}
										
										roleInterfaceList[field.name].push(contextField(FFun(functionDef), name, [], f.expr.pos));
									}
									else
									{
										//haxe.macro.Context.warning("The RoleMethod " + field.name + "." + name + " has no return type, add it if you need autocompletion.", f.expr.pos);
									}
									
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
		var type = roleInterfaces.exists(roleName) ? roleInterfaces[roleName] : null;
				
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
