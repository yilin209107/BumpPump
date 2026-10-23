import Foundation
import ImageIO
import UniformTypeIdentifiers
import PDFKit

/// Only called for URLs selected by the user in the attachment picker.
/// Paths are never exposed as agent tools; attachments contain bounded copies.
enum AgentAttachments {
  static func load(_ url:URL) throws -> AgentAttachment {
    let accessed=url.startAccessingSecurityScopedResource();defer{if accessed{url.stopAccessingSecurityScopedResource()}}
    let values=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
    guard values.isRegularFile==true,(values.fileSize ?? Int.max)<=20_000_000 else {throw AgentFailure("请选择20MB以内的普通文件。")}
    let type=UTType(filenameExtension:url.pathExtension.lowercased())
    if type?.conforms(to:.image)==true {
      guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1600,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else {throw AgentFailure("无法读取这张图片。")}
      let data=NSMutableData();guard let destination=CGImageDestinationCreateWithData(data,UTType.jpeg.identifier as CFString,1,nil) else {throw AgentFailure("无法处理这张图片。")}
      CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.82] as CFDictionary)
      guard CGImageDestinationFinalize(destination),data.length<=3_000_000 else {throw AgentFailure("图片处理后仍过大，请裁剪后重试。")}
      return .init(name:url.lastPathComponent,mime:"image/jpeg",image:data as Data)
    }
    if type?.conforms(to:.pdf)==true {
      guard let document=PDFDocument(url:url),!document.isLocked else {throw AgentFailure("PDF无法读取或需要密码。")}
      guard document.pageCount<=30 else {throw AgentFailure("请将PDF拆成30页以内的文件。")}
      let text=(0..<document.pageCount).compactMap{document.page(at:$0)?.string}.joined(separator:"\n")
      guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw AgentFailure("这份PDF没有可提取文字；扫描页请转成图片添加。")}
      guard text.count<=60000 else{throw AgentFailure("PDF文字过多，请只添加相关页面。")}
      return .init(name:url.lastPathComponent,mime:"application/pdf",text:text)
    }
    guard ["md","csv","json","txt","log","tsv"].contains(url.pathExtension.lowercased()),(values.fileSize ?? 0)<=2_000_000 else {throw AgentFailure("目前支持图片、文字PDF、TXT、Markdown、CSV及JSON文件。")}
    let data=try Data(contentsOf:url)
    guard let text=String(data:data,encoding:.utf8),text.count<=60000,!text.contains("\0") else {throw AgentFailure("请选择六万字以内的UTF-8文本文件。")}
    return .init(name:url.lastPathComponent,mime:type?.preferredMIMEType ?? "text/plain",text:text)
  }
}
