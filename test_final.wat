(module
  (memory (export "memory") 1)
  (func (export "allocate") (param i32) (result i32) (i32.const 1048576))
  (func (export "deallocate") (param i32))
  (func (export "interface_version_8"))
)
