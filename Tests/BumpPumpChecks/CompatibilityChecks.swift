import SwiftUI
import Charts

@main enum CompatibilityChecks {
  static func main() {
    var checks=0
    func check(_ value:Bool,_ title:String){precondition(value,title);checks += 1}
    let bounds=CGRect(x:0,y:0,width:200,height:200)
    let full=AppRingArc(start:0,end:1,innerRatio:0.75,gap:2).path(in:bounds)
    check(!full.contains(CGPoint(x:100,y:100)),"Ventura ring must preserve its transparent centre")
    check(full.contains(CGPoint(x:100,y:10)),"A full sector should fill its outer annulus")
    check(!full.contains(CGPoint(x:100,y:-2)),"The ring must stay inside its frame")
    let quarter=AppRingArc(start:0,end:0.25,innerRatio:0.75,gap:2).path(in:bounds)
    check(quarter.contains(CGPoint(x:162,y:38)),"The first quarter starts at noon and runs clockwise")
    check(!quarter.contains(CGPoint(x:38,y:162)),"Other sectors must remain unfilled")
    check(!quarter.contains(CGPoint(x:100,y:10)),"Angular gaps must separate adjacent sectors")
    check(AppRingArc(start:0,end:0,innerRatio:0.75,gap:2).path(in:bounds).isEmpty,"Zero values must not draw a sector")
    check(AppRingArc(start:0,end:1,innerRatio:0.75,gap:2).path(in:.zero).isEmpty,"Empty layouts must not produce invalid paths")
    let tiny=AppRingArc(start:0,end:0.00001,innerRatio:0.75,gap:2).path(in:bounds)
    check(!tiny.isEmpty && !tiny.contains(CGPoint(x:100,y:100)),"Very small values retain a valid annular path")
    print("macOS compatibility checks: \(checks) assertions passed; legacy ring geometry exercised on current host")
  }
}
