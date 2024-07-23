use std::sync::Arc;

use mlua::{ExternalResult, Function, IntoLua, Lua, MultiValue, Table, Value};

use super::LOADER;
use crate::RtRef;

pub(super) struct Require;

impl Require {
	pub(super) fn install(lua: &Lua) -> mlua::Result<()> {
		let globals = lua.globals();

		globals.raw_set(
			"require",
			lua.create_function(|lua, id: mlua::String| {
				let s = id.to_str()?;
				futures::executor::block_on(LOADER.ensure(s)).into_lua_err()?;

				lua.named_registry_value::<RtRef>("rt")?.push(s);
				let mod_ = LOADER.load(lua, s);
				lua.named_registry_value::<RtRef>("rt")?.pop();

				Self::create_mt(lua, s, mod_?)
			})?,
		)?;

		Ok(())
	}

	fn create_mt<'a>(lua: &'a Lua, id: &str, mod_: Table<'a>) -> mlua::Result<Table<'a>> {
		let ts = lua.create_table_from([("_mod", mod_.into_lua(lua)?)])?;

		let id: Arc<str> = Arc::from(id);
		let mt = lua.create_table_from([(
			"__index",
			lua.create_function(move |lua, (ts, key): (Table, mlua::String)| {
				match ts.raw_get::<_, Table>("_mod")?.raw_get::<_, Value>(&key)? {
					Value::Function(_) => Self::create_wrapper(lua, id.clone(), key.to_str()?)?.into_lua(lua),
					v => Ok(v),
				}
			})?,
		)])?;

		ts.set_metatable(Some(mt));
		Ok(ts)
	}

	fn create_wrapper<'a>(lua: &'a Lua, id: Arc<str>, f: &str) -> mlua::Result<Function<'a>> {
		let f: Arc<str> = Arc::from(f);

		lua.create_function(move |lua, (ts, args): (Table, MultiValue)| {
			let f: Function = ts.raw_get::<_, Table>("_mod")?.raw_get(&*f)?;
			let args = MultiValue::from_iter([ts.into_lua(lua)?].into_iter().chain(args));

			lua.named_registry_value::<RtRef>("rt")?.push(&id);
			let result = f.call::<_, MultiValue>(args);
			lua.named_registry_value::<RtRef>("rt")?.pop();

			result
		})
	}
}
