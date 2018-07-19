module Grammar where 

data Reserved = KWand | KWdownto | KWif | KWor | KWthen | 
    KWarray | KWelse | KWin | KWpacked | KWto | KWbegin | 
    KWend | KWlabel | KWprocedure | KWtype | KWcase | 
    KWfile | KWmod | KWprogram | KWuntil | KWconst | 
    KWfor | KWnil | KWrecord | KWvar | KWdiv | KWfunction |
    KWnot | KWrepeat | KWwhile | KWdo | KWgoto | KWof | 
    KWset | KWwith | KWboolean | KWreal | KWinteger |
    KWstring | KWchar deriving (Show, Eq)

data OP = OPplus | OPminus | OPstar | OPdiv | OPidiv | OPmod | 
    OPand | OPeq | OPneq | OPless | OPgreater | OPle | OPge | 
    OPin | OPor deriving (Show, Eq)
-- data OPunary = OPunary OP deriving (Show)
-- data OPadd = OPadd OP deriving (Show)
-- data OPmult = OPmult OP deriving (Show)
-- data OPrelation = OPrelation OP deriving (Show)
-- data Number = NUMint Int | NUMreal Double deriving (Show)

data Type = TYident Ident | TYchar | TYbool |
    TYint | TYreal | TYstr deriving (Show, Eq)
data Ident = Ident String deriving (Show, Eq)
data IdentList = IdentList [Ident] deriving (Show)

data Program = Program Ident Block deriving (Show)
data Block = Block [Decl] Statement deriving (Show)

data Decl = DeclVar [VarDecl] 
    | DeclType [TypeDecl] 
    | DeclConst [ConstDecl] 
    | DeclProc ProcDecl
    | DeclFunc FuncDecl 
    deriving (Show)
data VarDecl = VarDecl IdentList Type deriving (Show)
data TypeDecl = TypeDecl IdentList Type deriving (Show)
data ConstDecl = ConstDecl deriving (Show) -- todo 

data ProcDecl = ProcDecl Ident [FormalParam] Block deriving (Show) 
data FuncDecl = FuncDecl Ident [FormalParam] Type Block deriving (Show) 
-- data ProcHead = ProcHead Ident [FormalParam]
-- data FuncHead = FuncHead Ident [FormalParam]
data FormalParam = FormalParam Bool IdentList Type deriving (Show) 

data Statement = StatementSeq [Statement]  |
    Assignment Designator Expr |
    ProcCall Ident (Maybe ExprList) |
    StatementIf Expr Statement (Maybe Statement) |
    StatementCase | -- todo
    StatementWhile Expr Statement |
    StatementRepeat Statement Expr |
    StatementFor Ident Expr ToDownTo Expr Statement |
    StatementIO StatementIO |
    StatementMem Mem Ident |
    StatementEmpty  deriving (Show)
data StatementIO = StatmentRead DesigList | StatementReadLn DesigList |
    StatementWrite ExprList | StatementWriteLn ExprList deriving (Show) 
data Mem = MemNew | MemDispose deriving (Show) 
type ToDownTo = Bool

data Designator = Designator Ident [DesigProp] deriving (Show)
data DesigList = DesigList [Designator] deriving (Show)
data DesigProp = DesigPropIdent Ident | DesigPropExprList ExprList | 
    DesigPropPtr deriving (Show)

data ExprList = ExprList [Expr] deriving (Show)
data Expr = Relation Expr OP Expr
    | Unary OP Expr
    | Mult Expr OP Expr
    | Add Expr OP Expr
    | FactorInt Int | FactorReal Double 
    | FactorStr String 
    | FactorTrue | FactorFalse 
    | FactorNil 
    | FactorDesig Designator 
    | FactorNot Expr
    | FuncCall Ident (Maybe ExprList)
    deriving (Show)
