This is my high level pipeline idea for how umi code will be compiled.


```
[Source code: []u8] -> [tokenizer: []token] -> [parser: TopLevel] -> [optimizer: TopLevel]
                                                                               ||
                                                                               \/
                                                                     [IR translator: TAC ]
                                                                               ||
                                                                               \/
                                                               [Register Allocator: TAC w/ Context]
                                                                   ||                        ||
                                                                   \/                        \/
                                                           {virtual machine}           {machine code}
```
