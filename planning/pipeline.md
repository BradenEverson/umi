This is my high level pipeline idea for how umi code will be compiled. Still need to decide if we need an IR or not, or if going straight from toplevel to bytecode can be an acceptable IR :)


```
[Source code: []u8] -> [tokenizer: []token] -> [parser: TopLevel] -> [optimizer: TopLevel]
                                                                            ||
                                                                            \/
                                                                 [IR translator: TAC? Maybe ]
                                                                            ||
                                                                            \/
                                                          [bytecode compiler: cpool + bytecode]
                                                           ||                               ||
                                                           \/                               \/
                                                   {virtual machine}                  {machine code}
```
