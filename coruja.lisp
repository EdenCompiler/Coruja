;;;; ============================================================================
;;;; CORUJA — Conhecimento Organizado por Regras, Unificação e Julgamento
;;;;          Automático.  (coruja.lisp)
;;;; ----------------------------------------------------------------------------
;;;; Um sistema de conhecimento (knowledge system) educacional escrito em
;;;; Common Lisp, construído de forma DIRIGIDA POR MACROS (macro-driven).
;;;;
;;;; A coruja é símbolo de sabedoria — nome à altura de um sistema que deduz
;;;; conhecimento novo a partir do que já sabe.
;;;;
;;;; Objetivo didático: ensinar como representar fatos, regras e consultas
;;;; usando o recurso mais poderoso de Lisp — as macros — para criar uma
;;;; pequena Linguagem Específica de Domínio (DSL).
;;;;
;;;; Leia este arquivo de cima para baixo como um tutorial. Cada seção começa
;;;; com uma explicação em português e termina com código comentado.
;;;;
;;;; Como rodar (SBCL):
;;;;     sbcl --script coruja.lisp
;;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; SEÇÃO 0 — Pacote
;;; ----------------------------------------------------------------------------
;;; Em Lisp, símbolos vivem dentro de "pacotes" (namespaces). Criamos um pacote
;;; próprio para não poluir o pacote padrão e para deixar claro o que é a API
;;; pública do nosso sistema.

(defpackage :coruja
  (:use :common-lisp)
  (:nicknames :sc)
  (:export :definir-fato        ; macro: adiciona um fato à base
           :definir-fatos       ; macro: adiciona vários fatos de uma vez
           :esquecer            ; macro: retrata (remove) um fato
           :definir-regra       ; macro: adiciona uma regra de inferência
           :definir-regras      ; macro: adiciona várias regras de uma vez
           :definir-embutido    ; macro: cria um predicado embutido (em Lisp)
           :consultar           ; macro: faz uma pergunta à base
           :contar              ; macro: conta quantas respostas existem
           :todos               ; macro: coleta todos os valores (findall)
           :limpar-base         ; função: zera a base de conhecimento
           :explicar            ; macro: mostra o "porquê" de uma resposta
           :listar-fatos        ; função: imprime todos os fatos conhecidos
           :salvar-base         ; função: grava a base num arquivo
           :carregar-base       ; função: lê a base de um arquivo
           :*trace-prova*       ; variável: liga/desliga o rastro de inferência
           :*base*))            ; variável: a base de conhecimento global

(in-package :coruja)

;;; ----------------------------------------------------------------------------
;;; SEÇÃO 1 — O que é um "fato" e onde ele mora
;;; ----------------------------------------------------------------------------
;;; Um FATO é uma afirmação verdadeira sobre o mundo. Vamos representá-lo como
;;; uma simples lista (a estrutura de dados nativa de Lisp):
;;;
;;;     (gosta bruno lisp)   ; significa: "bruno gosta de lisp"
;;;     (pai joao maria)     ; significa: "joao é pai de maria"
;;;
;;; O primeiro elemento é o PREDICADO (a relação). Os demais são os ARGUMENTOS.
;;;
;;; A BASE DE CONHECIMENTO é apenas uma coleção de fatos. Usamos uma tabela
;;; hash indexada pelo predicado para que a busca seja rápida.

(defvar *base* (make-hash-table :test 'eql)
  "Base de conhecimento. Chave = predicado (símbolo). Valor = lista de fatos.")

(defun limpar-base ()
  "Apaga todo o conhecimento. Útil entre exemplos e em testes."
  (clrhash *base*)
  (values))

;;; ----------------------------------------------------------------------------
;;; SEÇÃO 2 — Por que MACROS?
;;; ----------------------------------------------------------------------------
;;; Poderíamos adicionar um fato com uma função normal:
;;;
;;;     (adicionar-fato '(gosta bruno lisp))
;;;
;;; Repare nas aspas (a apóstrofe '). Elas são ruído sintático: o usuário
;;; precisa lembrar de "citar" a lista para que ela não seja avaliada como
;;; uma chamada de função.
;;;
;;; MACROS recebem o código NÃO AVALIADO. Isso nos deixa criar uma sintaxe
;;; limpa, sem aspas, que parece uma linguagem nova:
;;;
;;;     (definir-fato gosta bruno lisp)
;;;
;;; A macro transforma essa escrita amigável no código real que roda. Essa é
;;; a essência de um sistema "macro-driven": a DSL é a interface; as macros
;;; fazem a tradução para Lisp comum em tempo de compilação.

;;; Função auxiliar (motor interno). Macros vão expandir PARA chamadas dela.
(defun %registrar-fato (fato)
  "Insere FATO na base, evitando duplicatas. Retorna o fato."
  (let* ((predicado (first fato))
         (existentes (gethash predicado *base*)))
    (unless (member fato existentes :test #'equal)
      (setf (gethash predicado *base*)
            (cons fato existentes)))
    fato))

;;; A MACRO. Recebe (definir-fato gosta bruno lisp) e gera, em tempo de
;;; compilação, o código:  (%registrar-fato '(gosta bruno lisp))
(defmacro definir-fato (predicado &rest argumentos)
  "Declara um fato verdadeiro. Uso: (definir-fato pai joao maria)."
  `(%registrar-fato '(,predicado ,@argumentos)))

;;; LOTE: declarar vários fatos com uma macro só. Repare como uma macro pode
;;; GERAR OUTRAS CHAMADAS de macro — aqui ela expande para um `progn` cheio de
;;; `definir-fato`. É composição de DSL: macro construída sobre macro.
;;;
;;;     (definir-fatos
;;;       (pai joao maria)
;;;       (pai joao pedro)
;;;       (mae lucia maria))
(defmacro definir-fatos (&body fatos)
  "Declara vários fatos de uma vez. Cada item é uma lista (predicado args...)."
  `(progn
     ,@(mapcar (lambda (f) `(definir-fato ,@f)) fatos)
     (values)))

;;; RETRATAR: remover um fato que deixou de ser verdade. Conhecimento muda;
;;; um bom sistema sabe esquecer.
(defun %esquecer-fato (fato)
  "Remove FATO da base, se existir. Retorna T se removeu, NIL caso contrário."
  (let* ((predicado (first fato))
         (antes (gethash predicado *base*))
         (depois (remove fato antes :test #'equal)))
    (setf (gethash predicado *base*) depois)
    (/= (length antes) (length depois))))

(defmacro esquecer (predicado &rest argumentos)
  "Retrata (remove) um fato. Uso: (esquecer gosta bruno java)."
  `(%esquecer-fato '(,predicado ,@argumentos)))

;;; ----------------------------------------------------------------------------
;;; SEÇÃO 3 — Unificação: o coração da consulta
;;; ----------------------------------------------------------------------------
;;; Para responder perguntas, precisamos COMPARAR um padrão com fatos. Um
;;; padrão pode conter VARIÁVEIS, que escrevemos como símbolos começando com
;;; "?":
;;;
;;;     (gosta bruno ?o-que)   ; "do que bruno gosta?"  ?o-que é variável
;;;
;;; UNIFICAR = encontrar valores para as variáveis que tornem o padrão igual
;;; ao fato. O resultado é uma lista de ligações (bindings), tipo
;;; ((?o-que . lisp)). Se não casar, devolvemos a flag :falha.

(defun variavel-p (x)
  "Verdadeiro se X é uma variável de padrão, isto é, símbolo iniciado em ?."
  (and (symbolp x)
       (> (length (symbol-name x)) 0)
       (char= (char (symbol-name x) 0) #\?)))

(defconstant +sem-ligacoes+ '((t . t))
  "Conjunto de ligações vazio porém bem-sucedido (não é :falha).")

(defun valor-ligado (variavel ligacoes)
  "Devolve o valor associado a VARIAVEL em LIGACOES, ou NIL se livre."
  (cdr (assoc variavel ligacoes)))

(defun unificar (a b &optional (ligacoes +sem-ligacoes+))
  "Tenta casar A com B. Retorna ligações estendidas ou :falha."
  (cond
    ((eq ligacoes :falha) :falha)
    ((eql a b) ligacoes)                       ; iguais: nada a fazer
    ((variavel-p a) (unificar-variavel a b ligacoes))
    ((variavel-p b) (unificar-variavel b a ligacoes))
    ((and (consp a) (consp b))                 ; listas: unifica elemento a elemento
     (unificar (rest a) (rest b)
               (unificar (first a) (first b) ligacoes)))
    (t :falha)))

(defun unificar-variavel (variavel valor ligacoes)
  "Liga VARIAVEL a VALOR, respeitando ligações já feitas."
  (let ((ja (assoc variavel ligacoes)))
    (cond
      (ja (unificar (cdr ja) valor ligacoes))  ; já tem valor: precisa bater
      (t (cons (cons variavel valor) ligacoes)))))

;;; ----------------------------------------------------------------------------
;;; SEÇÃO 4 — Regras: conhecimento que gera conhecimento
;;; ----------------------------------------------------------------------------
;;; Fatos são verdades diretas. REGRAS dizem "se isto, então aquilo" e deixam
;;; o sistema DEDUZIR fatos novos. Exemplo: avô é pai do pai.
;;;
;;;     (definir-regra (avo ?x ?z)         ; CABEÇA (conclusão)
;;;       (pai ?x ?y)                      ; CORPO (condições) ...
;;;       (pai ?y ?z))                     ; ... todas precisam ser verdade
;;;
;;; Guardamos regras como (cabeça . corpo). A macro novamente nos dá uma
;;; sintaxe sem aspas.

(defvar *regras* '()
  "Lista de regras. Cada regra é (CABEÇA . LISTA-DE-CONDIÇÕES).")

(defun %registrar-regra (cabeca corpo)
  "Motor interno: guarda uma regra. Macro definir-regra expande para cá."
  (push (cons cabeca corpo) *regras*)
  cabeca)

(defmacro definir-regra (cabeca &body corpo)
  "Declara uma regra de inferência.
   Uso: (definir-regra (avo ?x ?z) (pai ?x ?y) (pai ?y ?z))."
  `(%registrar-regra ',cabeca ',corpo))

;;; LOTE de regras — espelha `definir-fatos`. Cada item é uma regra completa
;;; (cabeça seguida do corpo). Mais uma vez: macro que expande para macros.
;;;
;;;     (definir-regras
;;;       ((avo ?x ?z) (pai ?x ?y) (pai ?y ?z))
;;;       ((irmao ?a ?b) (pai ?p ?a) (pai ?p ?b) (diferente ?a ?b)))
(defmacro definir-regras (&body regras)
  "Declara várias regras de uma vez. Cada item é (CABEÇA CONDIÇÃO...)."
  `(progn
     ,@(mapcar (lambda (r) `(definir-regra ,(first r) ,@(rest r))) regras)
     (values)))

;;; ----------------------------------------------------------------------------
;;; SEÇÃO 5 — O motor de inferência (provador)
;;; ----------------------------------------------------------------------------
;;; "Provar" um objetivo = achar todas as ligações que o tornam verdadeiro,
;;; usando (a) fatos diretos e (b) regras aplicadas recursivamente.
;;;
;;; Retornamos uma LISTA de conjuntos de ligações: uma para cada resposta
;;; possível. Lista vazia significa "não consegui provar".

(defun renomear-variaveis (expr sufixo)
  "Dá nomes únicos às variáveis de uma regra, evitando colisão entre usos.
   Cada ativação de regra recebe um SUFIXO numérico próprio."
  (cond
    ((variavel-p expr)
     (intern (format nil "~A-~A" (symbol-name expr) sufixo) :coruja))
    ((consp expr) (cons (renomear-variaveis (first expr) sufixo)
                        (renomear-variaveis (rest expr) sufixo)))
    (t expr)))

(defvar *contador* 0
  "Gerador de sufixos únicos para renomear variáveis de regras.")

;;; --- Predicados EMBUTIDOS (built-in) ---------------------------------------
;;; Alguns predicados não dão para guardar como fatos: pense em "x é diferente
;;; de y". Em vez de listar todos os pares diferentes do universo, calculamos
;;; a resposta em Lisp. Um predicado embutido é uma função que recebe os
;;; argumentos (já com as variáveis substituídas) e as ligações atuais, e
;;; devolve uma lista de ligações solução (vazia = falhou).
;;;
;;; Isso conecta a DSL lógica ao poder total de Lisp — uma "fuga" controlada.

(defvar *embutidos* (make-hash-table :test 'eql)
  "Tabela predicado -> função Lisp. Predicados calculados, não armazenados.")

(defmacro definir-embutido (predicado (args ligacoes) &body corpo)
  "Define um predicado calculado em Lisp.
   CORPO deve devolver uma lista de ligações solução (use LIGACOES para sucesso
   sem novas ligações, ou NIL para falha).
   Uso: (definir-embutido diferente (args ligacoes) ...)."
  `(setf (gethash ',predicado *embutidos*)
         (lambda (,args ,ligacoes)
           (declare (ignorable ,args ,ligacoes))
           ,@corpo)))

;;; `diferente`: sucesso se os dois argumentos forem termos distintos e ambos
;;; já estiverem ligados (sem variáveis livres). Habilita regras como `irmao`.
(definir-embutido diferente (args ligacoes)
  (let ((a (first args)) (b (second args)))
    (if (and (not (variavel-p a)) (not (variavel-p b)) (not (eql a b)))
        (list ligacoes)
        '())))

;;; `igual`: o espelho de `diferente`. Útil em guardas de regra.
(definir-embutido igual (args ligacoes)
  (let ((a (first args)) (b (second args)))
    (if (eql a b) (list ligacoes) '())))

;;; --- Embutidos ARITMÉTICOS ---
;;; A DSL lógica não sabe somar ou comparar números — mas Lisp sabe. Os
;;; embutidos abaixo trazem aritmética para dentro das regras. `maior` e
;;; `menor` são testes (guardas); `soma` é construtivo: LIGA o último argumento
;;; ao resultado, casando-o com unificação (pode estar livre ou já ter valor).

(definir-embutido maior (args ligacoes)
  "(maior ?a ?b) vale se ambos forem números e ?a > ?b."
  (let ((a (first args)) (b (second args)))
    (if (and (numberp a) (numberp b) (> a b)) (list ligacoes) '())))

(definir-embutido menor (args ligacoes)
  "(menor ?a ?b) vale se ambos forem números e ?a < ?b."
  (let ((a (first args)) (b (second args)))
    (if (and (numberp a) (numberp b) (< a b)) (list ligacoes) '())))

(definir-embutido soma (args ligacoes)
  "(soma A B ?r) liga ?r a A+B. A e B precisam ser números."
  (let ((a (first args)) (b (second args)) (r (third args)))
    (if (and (numberp a) (numberp b))
        (let ((nova (unificar r (+ a b) ligacoes)))   ; casa resultado por unificação
          (if (eq nova :falha) '() (list nova)))
        '())))

;;; --- RASTRO de inferência (trace) ------------------------------------------
;;; Ligando *trace-prova*, o motor narra cada objetivo que tenta provar, com
;;; indentação proporcional à profundidade da recursão. Ótimo para ENXERGAR o
;;; backtracking acontecendo — a melhor forma de entender o motor é vê-lo
;;; pensar em voz alta.

(defvar *trace-prova* nil
  "Se verdadeiro, `provar` imprime cada objetivo tentado, indentado por nível.")

(defun %rastro (profundidade formato &rest args)
  "Imprime uma linha de rastro indentada, só quando *trace-prova* está ligado."
  (when *trace-prova*
    (format t "~&~vT~A~%" (* 2 profundidade)
            (apply #'format nil formato args))))

(defun provar (objetivo ligacoes &optional (profundidade 0))
  "Prova OBJETIVO sob LIGACOES. Devolve lista de ligações solução.
   PROFUNDIDADE serve apenas para indentar o rastro (*trace-prova*)."
  (%rastro profundidade "prova? ~A" (aplicar-ligacoes objetivo ligacoes))
  (let ((resultados '())
        (predicado (first objetivo)))
    ;; (0) Predicado embutido? Delega o cálculo à função Lisp registrada.
    (let ((fn (gethash predicado *embutidos*)))
      (when fn
        (let ((r (funcall fn (aplicar-ligacoes (rest objetivo) ligacoes) ligacoes)))
          (%rastro profundidade "  embutido ~A -> ~:[falha~;ok~]" predicado r)
          (return-from provar r))))
    ;; (a) Tentar casar com fatos diretos.
    (dolist (fato (gethash predicado *base*))
      (let ((novo (unificar objetivo fato ligacoes)))
        (unless (eq novo :falha)
          (%rastro profundidade "  fato ~A" fato)
          (push novo resultados))))
    ;; (b) Tentar cada regra cuja cabeça case com o objetivo.
    (dolist (regra *regras*)
      (let* ((sufixo (incf *contador*))
             (cabeca (renomear-variaveis (car regra) sufixo))
             (corpo  (renomear-variaveis (cdr regra) sufixo))
             (casa   (unificar objetivo cabeca ligacoes)))
        (unless (eq casa :falha)
          (%rastro profundidade "  regra ~A :-" (car regra))
          ;; Cabeça casou. Agora provar TODAS as condições do corpo.
          (dolist (solucao (provar-todos corpo casa (1+ profundidade)))
            (push solucao resultados)))))
    (nreverse resultados)))

(defun provar-todos (objetivos ligacoes &optional (profundidade 0))
  "Prova uma conjunção: TODOS os OBJETIVOS sob as mesmas LIGACOES."
  (if (null objetivos)
      (list ligacoes)                          ; nada a provar: sucesso trivial
      (let ((solucoes '()))
        (dolist (lig (provar (first objetivos) ligacoes profundidade))
          (dolist (resto (provar-todos (rest objetivos) lig profundidade))
            (push resto solucoes)))
        (nreverse solucoes))))

;;; NEGAÇÃO POR FALHA (negation as failure) — um conceito central da
;;; programação lógica. `(nao (objetivo))` tem sucesso QUANDO o objetivo NÃO
;;; pode ser provado. Cuidado didático: isto é "não consigo provar que sim",
;;; e não "provei que é falso" — supõe MUNDO FECHADO (tudo que é verdade está
;;; na base). Por isso só funciona bem com o objetivo já sem variáveis livres.
;;;
;;; Definido AQUI, depois de `provar`, porque precisa chamá-lo.
(definir-embutido nao (args ligacoes)
  "(nao (OBJETIVO)) vale se OBJETIVO não tiver nenhuma prova."
  (let ((objetivo (first args)))               ; o argumento é o objetivo negado
    (if (null (provar objetivo ligacoes))
        (list ligacoes)                        ; não provou -> negação vale
        '())))                                 ; provou -> negação falha

;;; ----------------------------------------------------------------------------
;;; SEÇÃO 6 — Consultar: a interface de perguntas
;;; ----------------------------------------------------------------------------
;;; A macro CONSULTAR recebe um padrão e imprime as respostas de forma legível,
;;; substituindo as variáveis pelos valores encontrados.
;;;
;;;     (consultar gosta bruno ?o-que)
;;;     => ?o-que = lisp
;;;
;;; Sem variáveis, vira uma pergunta sim/não:
;;;
;;;     (consultar pai joao maria)  => Sim.

(defun aplicar-ligacoes (expr ligacoes)
  "Substitui variáveis de EXPR pelos valores em LIGACOES (recursivamente)."
  (cond
    ((variavel-p expr)
     (let ((par (assoc expr ligacoes)))
       (if par (aplicar-ligacoes (cdr par) ligacoes) expr)))
    ((consp expr) (cons (aplicar-ligacoes (first expr) ligacoes)
                        (aplicar-ligacoes (rest expr) ligacoes)))
    (t expr)))

(defun variaveis-de (expr)
  "Coleta as variáveis presentes em EXPR, sem repetição."
  (cond
    ((variavel-p expr) (list expr))
    ((consp expr) (remove-duplicates
                   (append (variaveis-de (first expr))
                           (variaveis-de (rest expr)))))
    (t '())))

(defun %consultar (objetivo)
  "Motor interno da consulta. Imprime respostas. Retorna lista de soluções."
  (setf *contador* 0)
  (let* ((solucoes (provar objetivo +sem-ligacoes+))
         (variaveis (variaveis-de objetivo)))
    (cond
      ((null solucoes)
       (format t "~&Não. (não foi possível provar ~A)~%" objetivo))
      ((null variaveis)
       (format t "~&Sim.~%"))                  ; pergunta fechada, sem variáveis
      (t
       (dolist (sol solucoes)
         (format t "~&")
         (dolist (v variaveis)
           (format t "~A = ~A  " v (aplicar-ligacoes v sol)))
         (terpri))))
    solucoes))

(defmacro consultar (predicado &rest argumentos)
  "Pergunta à base. Variáveis começam com ?.
   Uso: (consultar avo joao ?neto)."
  `(%consultar '(,predicado ,@argumentos)))

;;; AGREGAÇÃO: às vezes não queremos as respostas, só QUANTAS existem.
;;; `contar` prova em silêncio e devolve o número de soluções.
;;;     (contar pai joao ?filho)  => 2
(defmacro contar (predicado &rest argumentos)
  "Conta quantas respostas o padrão tem, sem imprimi-las. Retorna inteiro."
  `(progn
     (setf *contador* 0)
     (length (provar '(,predicado ,@argumentos) +sem-ligacoes+))))

;;; COLETA (findall, no Prolog): reúne os valores de UMA variável de TODAS as
;;; soluções numa lista Lisp comum — pronta para `mapcar`, `reduce`, etc.
;;; Aqui a DSL devolve dados ao mundo Lisp, fechando o ciclo.
;;;     (todos ?filho (pai joao ?filho))  => (MARIA PEDRO)
(defmacro todos (variavel objetivo)
  "Coleta em uma lista o valor de VARIAVEL em cada solução de OBJETIVO."
  `(progn
     (setf *contador* 0)
     (mapcar (lambda (sol) (aplicar-ligacoes ',variavel sol))
             (provar ',objetivo +sem-ligacoes+))))

;;; ----------------------------------------------------------------------------
;;; SEÇÃO 7 — Ferramentas de inspeção
;;; ----------------------------------------------------------------------------

(defun listar-fatos ()
  "Imprime todos os fatos da base, agrupados por predicado."
  (format t "~&=== Fatos na base ===~%")
  (maphash (lambda (predicado fatos)
             (declare (ignore predicado))
             (dolist (f (reverse fatos))
               (format t "  ~A~%" f)))
           *base*)
  (values))

;;; PERSISTÊNCIA: gravar e ler a base. Como fatos são apenas listas, salvar é
;;; só imprimí-los de forma que possam ser lidos de volta com READ. Lisp é
;;; "homoicônico": dados e código compartilham a mesma representação textual.
(defun salvar-base (caminho)
  "Grava todos os fatos em CAMINHO (um por linha), legível por READ."
  (with-open-file (saida caminho :direction :output
                                 :if-exists :supersede
                                 :if-does-not-exist :create)
    (maphash (lambda (predicado fatos)
               (declare (ignore predicado))
               (dolist (f (reverse fatos))
                 (print f saida)))
             *base*))
  caminho)

(defun carregar-base (caminho)
  "Lê fatos de CAMINHO e os adiciona à base. Retorna quantos foram lidos."
  (let ((n 0))
    (with-open-file (entrada caminho :direction :input)
      (loop for fato = (read entrada nil :fim)
            until (eq fato :fim)
            do (%registrar-fato fato) (incf n)))
    n))

;;; EXPLICAR: mostra a resposta, quantas soluções existem E o objetivo já
;;; instanciado (com as variáveis trocadas pelos valores). É uma forma simples
;;; de "explicabilidade": vê-se o fato concreto que cada solução afirma.
(defun %explicar (objetivo)
  "Prova OBJETIVO e imprime cada solução como um fato concreto + a contagem."
  (setf *contador* 0)
  (let ((sols (provar objetivo +sem-ligacoes+)))
    (if (null sols)
        (format t "~&Não. (não foi possível provar ~A)~%" objetivo)
        (dolist (sol sols)
          (format t "~&  porque vale: ~A~%" (aplicar-ligacoes objetivo sol))))
    (format t "~&(~A solução(ões) encontrada(s))~%" (length sols))
    sols))

(defmacro explicar (predicado &rest argumentos)
  "Como CONSULTAR, mas mostra cada fato concreto provado e a contagem total."
  `(%explicar '(,predicado ,@argumentos)))

;;; ----------------------------------------------------------------------------
;;; SEÇÃO 8 — Demonstração
;;; ----------------------------------------------------------------------------
;;; Roda só quando o arquivo é executado diretamente. Serve de tutorial vivo:
;;; uma árvore genealógica pequena e algumas perguntas.

(defun demonstracao ()
  "Exemplo completo: monta uma base e faz consultas."
  (limpar-base)
  (setf *regras* '())

  (format t "~&~%########## DEMONSTRAÇÃO — CORUJA ##########~%~%")

  ;; --- Fatos em LOTE (macro definir-fatos) ---
  (definir-fatos
    (pai joao maria)
    (pai joao pedro)
    (pai pedro ana)
    (mae lucia maria)
    (idade joao 70)
    (idade pedro 45)
    (idade ana 18)
    (idade lucas 10)                          ; criança, p/ mostrar a negação
    (gosta bruno lisp)
    (gosta bruno macros)
    (gosta bruno java))                       ; vamos nos arrepender deste

  ;; --- Regras em LOTE (macro definir-regras) ---
  (definir-regras
    ((avo ?x ?z) (pai ?x ?y) (pai ?y ?z))
    ((ancestral ?x ?y) (pai ?x ?y))                    ; caso base
    ((ancestral ?x ?z) (pai ?x ?y) (ancestral ?y ?z))  ; caso recursivo
    ;; usa o embutido `diferente`: irmãos têm o mesmo pai, pessoas distintas
    ((irmao ?a ?b) (pai ?p ?a) (pai ?p ?b) (diferente ?a ?b))
    ;; usa o embutido aritmético `maior`: maior de idade tem idade > 17
    ((maior-de-idade ?p) (idade ?p ?i) (maior ?i 17))
    ;; usa NEGAÇÃO POR FALHA: menor é quem não é maior de idade
    ((menor-de-idade ?p) (idade ?p ?i) (nao (maior-de-idade ?p))))

  (listar-fatos)

  ;; --- ESQUECER: bruno nunca gostou de java mesmo ---
  (format t "~&~%--- Retratando: (esquecer gosta bruno java) ---~%")
  (esquecer gosta bruno java)

  (format t "~&~%--- Pergunta: do que bruno gosta? ---~%")
  (consultar gosta bruno ?o-que)

  (format t "~&~%--- Pergunta: joao é pai de maria? ---~%")
  (consultar pai joao maria)

  (format t "~&~%--- Pergunta: quem é avô de ana? ---~%")
  (consultar avo ?quem ana)

  (format t "~&~%--- Pergunta: quem são irmãos? (usa `diferente`) ---~%")
  (consultar irmao ?a ?b)

  (format t "~&~%--- Aritmética: quem é maior de idade? (usa `maior`) ---~%")
  (consultar maior-de-idade ?quem)

  (format t "~&~%--- Negação por falha: quem é menor de idade? (usa `nao`) ---~%")
  (consultar menor-de-idade ?quem)

  (format t "~&~%--- Embutido construtivo `soma`: 2 + 3 = ? ---~%")
  (consultar soma 2 3 ?resultado)

  (format t "~&~%--- Agregação: quantos filhos joao tem? ---~%")
  (format t "joao tem ~A filho(s).~%" (contar pai joao ?filho))

  (format t "~&~%--- Coleta (findall): lista dos filhos de joao ---~%")
  (format t "filhos = ~A~%" (todos ?filho (pai joao ?filho)))

  (format t "~&~%--- Explicar: ancestrais de ana ---~%")
  (explicar ancestral ?quem ana)

  ;; --- RASTRO de inferência: ligar *trace-prova* e ver o motor pensar ---
  (format t "~&~%--- Rastro (*trace-prova*): provando (avo ?quem ana) ---~%")
  (let ((*trace-prova* t))
    (consultar avo ?quem ana))

  ;; --- PERSISTÊNCIA: salva e relê a base ---
  (let ((arquivo "coruja-base.lisp"))
    (format t "~&~%--- Persistência: salvando em ~A e recarregando ---~%" arquivo)
    (salvar-base arquivo)
    (limpar-base)
    (format t "Base limpa. Fatos recarregados: ~A~%" (carregar-base arquivo)))

  (format t "~&~%########## FIM ##########~%")
  (values))

;;; Executa a demonstração quando rodado como script.
;;; (Em REPL interativo, chame (coruja::demonstracao) à mão.)
(eval-when (:execute)
  (demonstracao))

;;;; ============================================================================
;;;; EXERCÍCIOS PROPOSTOS (para o leitor)
;;;; ----------------------------------------------------------------------------
;;;; 1. Adicione `mae` às regras de `ancestral` (hoje só usa `pai`).
;;;; 2. Crie um embutido `produto` (multiplicação) espelhando `soma`.
;;;; 3. Faça `explicar` mostrar QUAIS regras/fatos foram usados (rastro de prova
;;;;    completo) — guarde a árvore de derivação durante `provar`.
;;;; 4. Adicione `occurs check` na unificação para evitar laços infinitos.
;;;; 5. Crie um embutido `conta` (agregação) que conte soluções dentro de uma
;;;;    regra, espelhando a macro `todos`.
;;;; 6. CUIDADO com a negação: descubra por que `(nao (maior ?x 0))` com `?x`
;;;;    livre dá resultado estranho. Pesquise "mundo fechado" e "negação segura".
;;;; ============================================================================
