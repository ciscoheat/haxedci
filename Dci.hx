package ;

import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Context;

using haxe.macro.ExprTools;

class Dci
{	
	#if macro
	@macro public static function context() : Array<Field>
	{
        var fields : Array<Field> = Context.getBuildFields();
		var contextClass = Context.getLocalClass().get();		
				
		var isStatic = function(a) { return a == Access.AStatic; };
		var isPublic = function(a) { return a == Access.APublic; };
		var hasRole = function(m) { return m.name == "role"; };		
		var thisMacro = macro this;
		
		for (field in fields)
		{
			// Only interactions (instance methods) need a context setter.
			if (Lambda.exists(field.access, isStatic)) continue;

			// Add @:allow(currentPackage) to fields annotated with @role
			if (Lambda.exists(field.meta, hasRole))
			{			
				if (Lambda.exists(field.access, isPublic))
					Context.error("A Context Role cannot be public.", field.pos);
									
				var pack = contextClass.pack.length > 0 ? contextClass.pack : [contextClass.name];
					
				field.meta.push( { name: ":allow", params: [macro $p{pack}], pos: Context.currentPos() } );				
			}
			
			switch(field.kind)
			{
				case FFun(f):
					if (f.expr == null) continue;

					// Set Context to current object after all method calls.
					injectCurrentContext(f.expr, thisMacro);
					
					switch(f.expr.expr)
					{
						case EBlock(exprs):
							exprs.unshift(setCurrentContext(thisMacro));
							
						case _:
					}
					
				case _:
			}
		}
		
		return fields;
	}
	
	@macro public static function role(typeExpr : Expr) : Array<Field>
	{
        var fields : Array<Field> = Context.getBuildFields();
		var contextName = getTypeName(typeExpr);
		var contextType : Type = Context.getType(contextName);
		var roleType = Context.getLocalType();
		var typePath = Context.toComplexType(contextType);
		
		var contextMacro = macro context;
		var currentContextMacro = macro var context : $typePath = Dci.currentContext;
		
		// Inject context local variable in RoleMethods.
		for (field in fields)
		{
			switch(field.kind)
			{
				case FFun(f):
					if (f.expr == null) continue;
					
					injectCurrentContext(f.expr, contextMacro);
					
					switch(f.expr.expr)
					{					
						case EBlock(exprs):
							
							// Inject self
							switch(Context.getLocalClass().get().kind)
							{
								case KAbstractImpl(a):
									var type = a.get().name;
									var fieldName = type.charAt(0).toLowerCase() + type.substr(1);
									exprs.unshift(macro var self = context.$fieldName);
									
								case _: Context.error("Expected Abstract class for Role.", Context.currentPos());
							}
							
							// Inject context
							exprs.unshift(currentContextMacro);
							
						case _:
					}
					
				case _:
			}
		}

		// Determine underlying type of abstract type
		var returnType = getUnderlyingTypeForAbstractClass(fields);
		
		// Add the abstract type constructor to the class.
		var funcArg = { value : null, type : null, opt : false, name : "rolePlayer" };
		var kind = FFun( { ret : returnType, expr : macro return rolePlayer, params : [], args : [funcArg] } );
		
        fields.push({
			name : "_new", 
			doc : null, 
			meta : [], 
			access : [AStatic, AInline, APublic], 
			kind : kind, 
			pos : Context.currentPos() 
		});

		return fields;
	}
	
	static function getUnderlyingTypeForAbstractClass(fields : Array<Field>) : Null<ComplexType>
	{
		if (fields.length == 0)	return null;
		
		// Test first field of class
		return switch(fields[0].kind)
		{
			// If a function, it's expressed as the type of the first argument.
			case FFun(f): return f.args[0].type;
			case _: 
				// If not a function, it has a "from T to T" definition and the second
				// argument should contain the type.
				switch(fields[1].kind)
				{
					case FFun(f): f.args[0].type;
					case _:	throw "Class body for abstract type expected, instead: " + Context.getLocalType();
				}
		}
	}
	
	static function setCurrentContext(field : Expr)
	{
		return macro Dci.currentContext = $field;
	}

	static function injectCurrentContext(e : Expr, field : Expr)
	{
		var cb = function(e : Expr) { injectCurrentContext(e, field); };
		
		switch(e.expr)
		{
			case EFunction(name, f):
				if (f.expr != null)
				{
					switch(f.expr.expr)
					{
						case EBlock(exprs):
							exprs.unshift(setCurrentContext(field));
							
						case _:
					}
				}
				
			case ETry(e, catches):
				for (c in catches)
				{
					switch(c.expr.expr)
					{
						case EBlock(exprs):
							exprs.unshift(setCurrentContext(field));
							
						case _:
					}
				}
				
			case ECall(e2, params):
				switch(e2.expr)
				{
					case EField(e3, field):
						if (field == "bind")
						{
							var warning = "Usage of 'bind' can have side-effects when calling another role " +
										  "method or context. Use an anonymous function instead to be safe.";
							Context.warning(warning, e3.pos);
						}
							
					case _:
				}
				
			case _:
		}
		
		e.iter(cb);
	}
	
	static function getTypeName(type) : String
	{
		switch(type.expr)
		{
			case EConst(c):
				switch(c)
				{
					case CIdent(s): return s;
					case _:
				}
				
			case _:
		}
		
		Context.error("Type identifier expected.", type.pos);
		return null;
	}
	#else
	/**
	 * Current context storage. Shouldn't be tampered with.
	 */ 
	public static var currentContext(default, default) : Dynamic;
	#end
}