import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Entry Point
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fullscreen Mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const GomokuApp());
}

// --- CẤU HÌNH BÀN CỜ ---
const int BOARD_SIZE = 15;
const int EMPTY = 0;
const int PLAYER = 1; // X
const int AI = 2;     // O

// --- AI BRAIN (Dùng thuật toán Max-Min cơ bản để siêu nhanh) ---
class Brain {
  static int findMove(List<int> board) {
    // 1. Thắng ngay
    int win = _scan(board, AI); 
    if (win != -1) return win;
    // 2. Chặn thua
    int block = _scan(board, PLAYER); 
    if (block != -1) return block;
    
    // 3. Tính điểm vùng (Heuristic)
    return _bestSpot(board);
  }

  static int _scan(List<int> b, int p) {
    for(int i=0; i<225; i++) {
      if(b[i] == EMPTY) {
        b[i] = p;
        if(_check5(b, i, p)) { b[i]=EMPTY; return i; }
        b[i] = EMPTY;
      }
    }
    return -1;
  }

  static int _bestSpot(List<int> b) {
    int best = -1;
    int maxScore = -1;
    for(int i=0; i<225; i++) {
      if(b[i]==EMPTY && _hasNeighbor(b, i)) {
        // Công thức: (Điểm công AI) + (Điểm thủ chặn Player)
        int score = _rate(b, i, AI) + _rate(b, i, PLAYER);
        if(score > maxScore) { maxScore = score; best = i; }
      }
    }
    // Nếu bàn cờ trống, đánh vào giữa (112)
    return best == -1 ? 112 : best;
  }

  static bool _hasNeighbor(List<int> b, int idx) {
    int r=idx~/15, c=idx%15;
    for(int x=-1; x<=1; x++) for(int y=-1; y<=1; y++) {
      if(x==0 && y==0) continue;
      int nr=r+x, nc=c+y;
      if(nr>=0 && nr<15 && nc>=0 && nc<15 && b[nr*15+nc]!=EMPTY) return true;
    }
    return false;
  }

  static int _rate(List<int> b, int idx, int p) {
    // Giả lập logic đơn giản để code gọn
    // Càng nhiều quân liên tiếp càng nhiều điểm
    int r=idx~/15, c=idx%15;
    int total = 0;
    List<List<int>> ds = [[1,0], [0,1], [1,1], [1,-1]];
    for(var d in ds) {
      int count = 0;
      for(int k=1; k<5; k++) { // Duong
        int nr=r+d[1]*k, nc=c+d[0]*k;
        if(nr<0||nr>=15||nc<0||nc>=15) break;
        if(b[nr*15+nc]==p) count++; else break;
      }
      for(int k=1; k<5; k++) { // Am
        int nr=r-d[1]*k, nc=c-d[0]*k;
        if(nr<0||nr>=15||nc<0||nc>=15) break;
        if(b[nr*15+nc]==p) count++; else break;
      }
      if(count>=4) total += 10000;
      else if(count==3) total += 1000;
      else if(count==2) total += 100;
      else total += 10;
    }
    return total;
  }

  static bool _check5(List<int> b, int idx, int p) {
    // Check thắng thua
    int r=idx~/15, c=idx%15;
    List<List<int>> ds = [[1,0], [0,1], [1,1], [1,-1]];
    for(var d in ds) {
      int cMap = 1;
      for(int k=1; k<5; k++) { 
        int nr=r+d[1]*k, nc=c+d[0]*k;
        if(nr<0||nr>=15||nc<0||nc>=15||b[nr*15+nc]!=p) break; cMap++;
      }
      for(int k=1; k<5; k++) { 
        int nr=r-d[1]*k, nc=c-d[0]*k;
        if(nr<0||nr>=15||nc<0||nc>=15||b[nr*15+nc]!=p) break; cMap++;
      }
      if(cMap>=5) return true;
    }
    return false;
  }
}

// --- UI APP ---
class GomokuApp extends StatelessWidget {
  const GomokuApp({super.key});
  @override
  Widget build(BuildContext context) => const CupertinoApp(
    debugShowCheckedModeBanner: false,
    theme: CupertinoThemeData(brightness: Brightness.light),
    home: BoardView(),
  );
}

class BoardView extends StatefulWidget {
  const BoardView({super.key});
  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  List<int> board = List.filled(225, 0);
  String title = "iOS 18 Gomoku";
  bool busy = false;

  void tap(int i) async {
    if(board[i]!=0 || busy) return;
    
    // Human
    setState(() { board[i] = PLAYER; });
    if(Brain._check5(board, i, PLAYER)) { _alert("You Win!"); return; }

    // AI Thinking
    setState(() { busy = true; title="AI is thinking..."; });
    await Future.delayed(const Duration(milliseconds: 50)); // UI update
    
    // Compute
    List<int> clone = List.from(board);
    int aim = await compute(Brain.findMove, clone);
    
    setState(() {
      if(board[aim]==0) board[aim] = AI;
      busy = false; title="Your Turn";
    });

    if(Brain._check5(board, aim, AI)) { _alert("AI Wins!"); }
  }

  void _alert(String msg) {
    showCupertinoDialog(context: context, builder: (c)=>CupertinoAlertDialog(
      title: Text(msg),
      actions: [CupertinoDialogAction(child: const Text("New Game"), onPressed: (){
        Navigator.pop(c); setState((){board=List.filled(225, 0);});
      })]
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(20), child: Text(title, 
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5))),
          Expanded(
            child: Center(
              child: AspectRatio(aspectRatio: 1, child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0,5))]
                ),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 15),
                  itemCount: 225,
                  itemBuilder: (c,i) => GestureDetector(
                    onTap: ()=>tap(i),
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: CupertinoColors.systemGrey6)),
                      child: Center(child: _piece(board[i]))
                    )
                  )
                )
              ))
            )
          )
        ]),
      )
    );
  }

  Widget _piece(int v) {
    if(v==0) return const SizedBox();
    return Text(v==1?"✕":"◯", style: TextStyle(
      fontSize: 18, fontWeight: FontWeight.w900,
      color: v==1?CupertinoColors.activeBlue:CupertinoColors.systemRed
    ));
  }
}
