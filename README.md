# 🦉 CORUJA

**C**onhecimento **O**rganizado por **R**egras, **U**nificação e **J**ulgamento
**A**utomático.

Um sistema de conhecimento (*knowledge system*) **educacional**, escrito em um
único arquivo Common Lisp: [`coruja.lisp`](coruja.lisp). A coruja é símbolo de
sabedoria — nome à altura de um sistema que **deduz conhecimento novo** a partir
do que já sabe.

O objetivo não é ser um motor de produção, e sim **ensinar como construir um
sistema de conhecimento em Lisp usando macros**. O arquivo foi pensado para ser lido de cima
para baixo, como um tutorial.

---

## O que é um "sistema de conhecimento"?

É um programa que:

1. **Guarda fatos** sobre o mundo — ex.: "joão é pai de maria".
2. **Guarda regras** de inferência — ex.: "avô é o pai do pai".
3. **Responde perguntas** deduzindo respostas a partir de fatos + regras —
   ex.: "quem é avô de ana?".

A família clássica desses programas vem da Programação Lógica (o **Prolog** é o
exemplo mais famoso). Aqui construímos uma versão minúscula em Lisp.

---

## Por que Lisp? Por que macros?

Em Lisp, **código é dado**: um programa é apenas uma lista. Isso torna trivial
representar fatos como listas e — mais importante — permite criar **macros**.

Uma macro recebe o código **antes** de ele ser avaliado e o reescreve. Com isso
criamos uma **DSL** (Linguagem Específica de Domínio) limpa:

```lisp
;; Sem macro (função): precisa "citar" a lista com '
(adicionar-fato '(gosta bruno lisp))

;; Com macro: sintaxe limpa, parece uma linguagem nova
(definir-fato gosta bruno lisp)
```

Chamamos isso de estilo **macro-driven** (dirigido por macros): a interface do
usuário é uma DSL declarativa; as macros traduzem essa DSL para Lisp comum em
tempo de compilação. A DSL completa:

| Macro / função      | Para quê                              | Exemplo                                   |
|---------------------|---------------------------------------|-------------------------------------------|
| `definir-fato`      | declarar uma verdade                  | `(definir-fato pai joao maria)`           |
| `definir-fatos`     | declarar vários fatos de uma vez      | `(definir-fatos (pai joao maria) (pai joao pedro))` |
| `esquecer`          | retratar (remover) um fato            | `(esquecer gosta bruno java)`             |
| `definir-regra`     | declarar uma regra de inferência      | `(definir-regra (avo ?x ?z) (pai ?x ?y) (pai ?y ?z))` |
| `definir-regras`    | declarar várias regras de uma vez     | `(definir-regras ((avo ?x ?z) (pai ?x ?y) (pai ?y ?z)))` |
| `definir-embutido`  | predicado calculado em Lisp           | `(definir-embutido diferente (args lig) ...)` |
| `consultar`         | fazer uma pergunta                    | `(consultar avo ?quem ana)`               |
| `contar`            | contar respostas (agregação)          | `(contar pai joao ?filho)` → `2`          |
| `todos`             | coletar valores numa lista (findall)  | `(todos ?f (pai joao ?f))` → `(MARIA PEDRO)` |
| `explicar`          | respostas + fatos concretos provados  | `(explicar ancestral ?quem ana)`          |
| `salvar-base`       | gravar a base num arquivo             | `(salvar-base "/tmp/base.lisp")`          |
| `carregar-base`     | ler a base de um arquivo              | `(carregar-base "/tmp/base.lisp")`        |

### Predicados embutidos (built-in)

Alguns predicados não dá para listar como fatos — ex.: "x é diferente de y" ou
"a + b". A CORUJA os **calcula em Lisp** via `definir-embutido`. Já vêm prontos:

| Embutido    | Tipo         | O que faz                                            |
|-------------|--------------|------------------------------------------------------|
| `diferente` | teste        | `(diferente ?a ?b)` vale se os termos forem distintos |
| `igual`     | teste        | o espelho de `diferente`                             |
| `maior`     | teste        | `(maior ?a ?b)` vale se `?a > ?b` (números)          |
| `menor`     | teste        | `(menor ?a ?b)` vale se `?a < ?b` (números)          |
| `soma`      | construtivo  | `(soma 2 3 ?r)` **liga** `?r` a `5`                  |
| `nao`       | meta         | `(nao (OBJ))` vale se `OBJ` **não** pode ser provado |

Isso habilita regras como:

```lisp
(definir-regra (irmao ?a ?b)
  (pai ?p ?a)
  (pai ?p ?b)
  (diferente ?a ?b))         ; sem isto, todo mundo seria "irmão de si mesmo"

(definir-regra (maior-de-idade ?p)
  (idade ?p ?i)
  (maior ?i 17))             ; aritmética dentro da lógica
```

`definir-embutido` é a ponte entre a lógica declarativa e o poder total de
Lisp — você escreve a regra de cálculo em Lisp e ela vira um predicado da DSL.

### Negação por falha (negation as failure)

O embutido `nao` traz um conceito central da programação lógica:

```lisp
(definir-regra (menor-de-idade ?p)
  (idade ?p ?i)
  (nao (maior-de-idade ?p)))   ; "não consigo provar que é maior"
```

⚠️ **Cuidado educativo:** `(nao X)` significa *"não consigo provar X"*, e não
*"provei que X é falso"*. Isso supõe **mundo fechado** (tudo que é verdade está
na base) e só funciona bem quando `X` já não tem variáveis livres. É uma
armadilha clássica — e uma ótima lição.

### Rastro de inferência (trace)

Ligue `*trace-prova*` para ver o motor **pensar em voz alta** — cada objetivo
tentado, indentado pela profundidade da recursão:

```lisp
(let ((*trace-prova* t))
  (consultar avo ?quem ana))
;; prova? (AVO ?QUEM ANA)
;;   regra (AVO ?X ?Z) :-
;;     prova? (PAI ?X-6 ?Y-6)
;;       fato (PAI PEDRO ANA)
;;       ...
```

É a melhor forma de enxergar o *backtracking* acontecendo.

---

## Como rodar

Você precisa de uma implementação de Common Lisp. A mais comum é a
[SBCL](http://www.sbcl.org/).

### Modo script (roda a demonstração e sai)

```bash
sbcl --script coruja.lisp
```

### Modo interativo (REPL — recomendado para aprender)

```bash
sbcl --load coruja.lisp
```

E então, no prompt:

```lisp
(in-package :coruja)

(limpar-base)
(definir-fato gosta bruno lisp)
(definir-fato gosta bruno macros)
(consultar gosta bruno ?o-que)
;; => ?o-que = lisp
;; => ?o-que = macros
```

> Outras implementações (CCL, ECL, CLISP) também funcionam; troque só o comando
> de carregamento.

---

## Conceitos ensinados, na ordem do arquivo

O `.lisp` está dividido em seções numeradas. Cada uma introduz uma ideia:

0. **Pacotes** — organizar nomes e expor uma API pública.
1. **Representação de fatos** — fatos como listas; base como tabela hash.
2. **Macros vs. funções** — por que a DSL usa macros (sintaxe sem aspas).
3. **Unificação** — casar padrões com variáveis (`?x`) contra fatos. É o
   coração de qualquer motor lógico.
4. **Regras** — conhecimento que gera conhecimento.
5. **Motor de inferência** — provar objetivos com recursão e *backtracking*,
   inclusive renomeando variáveis para evitar colisões.
6. **Consulta** — transformar soluções internas em respostas legíveis.
7. **Inspeção** — `listar-fatos` e `explicar`.
8. **Demonstração** — uma árvore genealógica completa com perguntas.

---

## Variáveis de padrão

Qualquer símbolo começando com `?` é uma **variável** numa consulta ou regra:

```lisp
(consultar pai joao ?filho)   ; "quem são os filhos de joão?"
(consultar pai ?quem ana)     ; "quem é pai de ana?"
(consultar pai joao maria)    ; pergunta sim/não -> "Sim."
```

---

## Exemplo de saída da demonstração

```
--- Pergunta: quem são os ancestrais de ana? ---
?quem = pedro
?quem = joao
(2 solução(ões) encontrada(s))
```

`joao` aparece como ancestral de `ana` mesmo **sem nenhum fato direto** dizendo
isso — foi **deduzido** pela regra recursiva `ancestral`. Esse é o ponto alto:
o sistema sabe mais do que lhe foi dito.

---

## Exercícios

No fim do arquivo `.lisp` há exercícios propostos: adicionar `mae` às regras,
criar a relação `irmao`, escrever uma macro `definir-fatos` para vários fatos
de uma vez, e fazer `explicar` mostrar o rastro de prova.

---

## Limitações (de propósito)

Para manter o foco didático, este sistema **não** tem: negação, índices
avançados, *occurs check* na unificação, ou controle de loop infinito em regras
mal escritas. Cada limitação é uma boa oportunidade de estudo. 🙂
