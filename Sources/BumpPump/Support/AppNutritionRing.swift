import SwiftUI
import Charts

struct AppRingSegment:Identifiable {
  let name:String
  let value:Double
  let color:Color
  let accessibilityValue:String
  var id:String{name}
}
/// Swift Charts sectors arrived in macOS 14. Ventura draws the same proportions
/// with paths; its surrounding hover, labels and entrance animation are shared.
struct AppNutritionRing:View {
  let segments:[AppRingSegment]
  let innerRatio:Double
  let outerRatio:Double
  let gap:Double
  var cornerRadius:Double=2
  @ViewBuilder var body:some View {
    if #available(macOS 14,*) {
      Chart(segments){segment in
        SectorMark(angle:.value("热量",segment.value),innerRadius:.ratio(innerRatio),outerRadius:.ratio(outerRatio),angularInset:gap)
          .foregroundStyle(segment.color).cornerRadius(cornerRadius)
          .accessibilityLabel(segment.name).accessibilityValue(segment.accessibilityValue)
      }.chartLegend(.hidden)
    }else {
      GeometryReader { geometry in
        let total=segments.reduce(0){$0+max(0,$1.value)}
        let radius=min(geometry.size.width,geometry.size.height)*outerRatio/2
        ZStack {
          ForEach(Array(segments.enumerated()),id:\.element.id){index,segment in
            let start=segments.prefix(index).reduce(0){$0+max(0,$1.value)}/max(total,1)
            let end=start+max(0,segment.value)/max(total,1)
            AppRingArc(start:start,end:end,innerRatio:innerRatio/outerRatio,gap:gap)
              .fill(segment.color,style:FillStyle(eoFill:true)).frame(width:radius*2,height:radius*2)
              .accessibilityLabel(segment.name).accessibilityValue(segment.accessibilityValue)
          }
        }.frame(width:geometry.size.width,height:geometry.size.height)
      }
    }
  }
}
struct AppRingArc:Shape {
  let start:Double
  let end:Double
  let innerRatio:Double
  let gap:Double
  func path(in rect:CGRect)->Path {
    let radius=min(rect.width,rect.height)/2
    guard radius>0,end>start else{return Path()}
    let fullCircle=end-start>=0.999999
    if fullCircle {
      // Explicit even-odd ellipses avoid older Path arc normalization treating
      // a full reverse inner arc as another filled disc.
      var ring=Path()
      let outer=CGRect(x:rect.midX-radius,y:rect.midY-radius,width:radius*2,height:radius*2)
      ring.addEllipse(in:outer)
      ring.addEllipse(in:outer.insetBy(dx:radius*(1-innerRatio),dy:radius*(1-innerRatio)))
      return ring
    }
    let inset=min((end-start)*Double.pi*0.42,gap/max(1,radius)*0.5)
    let from=start*Double.pi*2-Double.pi/2+inset
    let to=end*Double.pi*2-Double.pi/2-inset
    let centre=CGPoint(x:rect.midX,y:rect.midY)
    var path=Path()
    path.addArc(center:centre,radius:radius,startAngle:.radians(from),endAngle:.radians(to),clockwise:false)
    path.addArc(center:centre,radius:radius*innerRatio,startAngle:.radians(to),endAngle:.radians(from),clockwise:true)
    path.closeSubpath()
    return path
  }
}
