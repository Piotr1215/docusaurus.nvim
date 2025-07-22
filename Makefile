.PHONY: test clean

test:
	nvim --headless -u test/minimal_init.lua -c "PlenaryBustedDirectory test/ { minimal_init = './test/minimal_init.lua' }"

clean:
	rm -rf /tmp/lazy-test /tmp/lazy.nvim /tmp/lazy-lock.json