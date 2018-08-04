{-# LANGUAGE OverloadedStrings #-}

module Emit where 

import qualified Intermediate as IR
import TypeCheck (isNum)
import qualified Grammar as G ( Type(..) )
import Grammar (OP(..), Ident, IdentList,
    VarDecl, TypeDecl, CallByRef, ToDownTo)

import Control.Monad.Except hiding (void)
import Control.Applicative

import Utils (p')
import Paskell as P

import LLVM.AST
import qualified LLVM.AST as AST
import qualified LLVM.AST.Constant as C
import qualified LLVM.AST.Float as F
import qualified LLVM.AST.IntegerPredicate as IP
import qualified LLVM.AST.FloatingPointPredicate as FP

import LLVM.AST.Global
import LLVM.Context
import LLVM.Module
import LLVM.AST.ParameterAttribute
import qualified Data.ByteString.Char8 as BS
import Data.ByteString.Short
import qualified ConvertIR as Conv
import qualified Intermediate as IR
import Codegen



toShortBS =  toShort . BS.pack 
toString = BS.unpack . fromShort
name' = Name . toShortBS

toLLVMType t = 
    case t of G.TYint  -> int
              G.TYbool -> bool
              G.TYreal -> double
              G.Void -> void

toParamList params = map mapParam params
    where mapParam (x,t,byref) = 
            Parameter (toLLVMType t) (name' x) (if byref then [Dereferenceable 4] else [])
-------------------------------------------------------

liftError :: ExceptT String IO a -> IO a
liftError = runExceptT >=> either fail return

codegen :: AST.Module -> [IR.Decl] -> IO AST.Module
codegen mod fns = withContext $ \context ->
  liftIO $ withModuleFromAST context newast $ \m -> do
    llstr <- moduleLLVMAssembly m
    putStrLn (BS.unpack llstr)
    return newast
  where
    modn    = mapM genDeclFunc fns
    newast = runLLVM mod modn

-------------------------

genDecl :: IR.Decl -> Codegen ()
genDecl d@(IR.DeclVar xs _) = genDeclVar d >> return ()
-- genDecl d@(IR.DeclFunc x args retty blk _) = genDeclFunc d

genDeclFunc (IR.DeclFunc x args retty blk _) = do
    define (toLLVMType retty) (toShortBS x) (toSig args) body
    where 
        toSig xs = map (\(a,b,c) -> (toLLVMType b, name' a)) xs
        body = do
            entry' <- addBlock (toShortBS "entry")
            setBlock entry'
            forM args $ \(i,t,_) -> do
                var <- alloca (toLLVMType t)
                store var (local (toLLVMType t) (name' i))
                assign (toShortBS i) var
            genBlock blk
            ret (cons (C.Int 32 (fromIntegral 1)))
        
genDeclProc (IR.DeclProc x args blk _) = do
    define (toLLVMType retty) (toShortBS x) (toSig args) body
    where 
        retty = G.Void
        toSig xs = map (\(a,b,c) -> (toLLVMType b, name' a)) xs
        body = do
            entry' <- addBlock (toShortBS "entry")
            setBlock entry'
            forM args $ \(i,t,_) -> do
                var <- alloca (toLLVMType t)
                store var (local (toLLVMType t) (name' i))
                assign (toShortBS i) var
            genBlock blk
            retvoid

genDeclVar (IR.DeclVar xs _) = forM xs $ \(i,t) -> do
    var <- alloca (toLLVMType t)
    assign (toShortBS i) var

genBlock :: IR.Block -> Codegen ()
genBlock (IR.Block ds s _) = do
    forM ds genDecl
    genStatement s


genStatement :: IR.Statement -> Codegen ()
genStatement (IR.StatementEmpty) = return ()
genStatement (IR.StatementSeq xs _) = (forM xs genStatement) >> return ()
genStatement (IR.Assignment (IR.Designator x _ xt) expr _) = do
    -- get %r value for rhs
    -- store  %r, pointer to x
    rhs <- genExpr expr
    var <- getvar $ toShortBS x
    store var rhs

genStatement (IR.StatementIf expr s1 ms2 _) = let 
    s2 = case ms2 of Nothing -> IR.StatementEmpty
                     Just x  -> x
    in do
        ifthen <- addBlock "if.then"
        ifelse <- addBlock "if.else"
        ifexit <- addBlock "if.exit"

        -- %entry
        ------------------
        cond <- genExpr expr
        _ <- cbr cond ifthen ifelse

        -- if.then
        _ <- setBlock ifthen
        then' <- genStatement s1
        _ <- br ifexit
        ifthen' <- getBlock

        -- if.else
        _ <- setBlock ifelse
        else' <- genStatement s2
        _ <- br ifexit
        ifelse' <- getBlock

        -- if.exit
        _ <- setBlock ifexit
        return ()

genStatement (IR.StatementFor x expr1 todownto expr2 s _) = undefined
    
genStatement (IR.StatementWhile expr s _) = undefined

genStatement (IR.ProcCall x xs t) = undefined

-- returns %x for final expression value, and stores any intermediate instructions in the block
genExpr :: IR.Expr -> Codegen Operand
genExpr (IR.FactorInt x  _) = return $ cons $ C.Int 32 (fromIntegral x)
genExpr (IR.FactorReal x _) = return $ cons $ C.Float (F.Double x)
genExpr (IR.FactorStr x _)  = undefined
genExpr (IR.FactorTrue _)   = return $ cons $ C.Int 1 1
genExpr (IR.FactorFalse _)  = return $ cons $ C.Int 1 0
genExpr (IR.Relation x1 op x2 _) = let 
    (t1,t2) = (IR.getType x1, IR.getType x2)
    cmpFloat y1 y2 = do
        fy1 <- if t1 == G.TYint then sitofp double y1 else return y1
        fy2 <- if t2 == G.TYint then sitofp double y2 else return y2
        case op of 
            OPless    -> fcmp FP.OLT fy1 fy2
            OPle      -> fcmp FP.OLE fy1 fy2
            OPgreater -> fcmp FP.OGT fy1 fy2
            OPge      -> fcmp FP.OGE fy1 fy2
            OPeq      -> fcmp FP.OEQ  fy1 fy2
            OPneq     -> fcmp FP.ONE  fy1 fy2
    cmpInt y1 y2 = do
        case op of 
            OPless    -> icmp IP.SLT y1 y2
            OPle      -> icmp IP.SLE y1 y2
            OPgreater -> icmp IP.SGT y1 y2
            OPge      -> icmp IP.SGE y1 y2
            OPeq      -> icmp IP.EQ  y1 y2
            OPneq     -> icmp IP.NE  y1 y2
    cmp = if t1 == G.TYreal || t2 == G.TYreal 
               then cmpFloat 
          else if t1 `elem` [G.TYint, G.TYbool] || t2 `elem` [G.TYint,G.TYbool]
               then cmpInt -- int and bool
               else undefined -- todo: other cases
    in do
        y1 <- genExpr x1
        y2 <- genExpr x2
        cmp y1 y2


genExpr (IR.Add x1 op x2 t) = do 
    y1 <- genExpr x1
    y2 <- genExpr x2
    case t of 
        G.TYbool -> undefined
        G.TYint  -> (if op == OPplus then iadd else isub) y1 y2
        G.TYreal -> do
            fy1 <- if IR.getType x1 == G.TYint then sitofp double y1 else return y1
            fy2 <- if IR.getType x2 == G.TYint then sitofp double y2 else return y2
            (if op == OPplus then fadd else fsub) fy1 fy2
            

genExpr (IR.Mult x1 op x2 t) = do
    y1 <- genExpr x1
    y2 <- genExpr x2
    case t of 
        G.TYbool -> undefined
        G.TYint  -> imul y1 y2
        G.TYreal -> do
            fy1 <- if IR.getType x1 == G.TYint then sitofp double y1 else return y1
            fy2 <- if IR.getType x2 == G.TYint then sitofp double y2 else return y2
            fmul fy1 fy2 -- todo replace fmul with case on op

genExpr (IR.Unary op x t) =  do
    y <- genExpr x
    case op of 
        OPor -> undefined
        OPplus -> return y
        OPminus -> genExpr $ IR.Add (IR.FactorInt 0 G.TYbool) op x t

genExpr (IR.FuncCall f xs t) = do
    args <- mapM genExpr xs
    call (externf (toLLVMType t) (name' f)) args

genExpr (IR.FactorDesig (IR.Designator x _ xt) _) = do
    var <- getvar $ toShortBS x
    load var