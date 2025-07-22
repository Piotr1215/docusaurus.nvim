.PHONY: test clean luacheck

test:
	nvim --headless -u test/minimal_init.lua -c "PlenaryBustedDirectory test/ { minimal_init = './test/minimal_init.lua' }"

luacheck:
	luacheck lua/ test/ --formatter plain

clean:
	rm -rf /tmp/lazy-test /tmp/lazy.nvim /tmp/lazy-lock.json