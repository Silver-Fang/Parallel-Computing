%[text] 在单线程环境下，读入一个数据块。
%[text] 此方法只能在构造该对象的进程上调用，多线程环境下则会发生争用，因此通常用于单线程环境，退化为读入-计算-写出的简单流程。多线程环境请使用RemoteRead Block/Async。
%[text] ## 语法
%[text] ```matlabCodeExample
%[text] [Data,BlockIndex]=obj.LocalReadBlock(ReadBytes=ReadBytes);
%[text] %读入不超过指定字节数的数据，根据绑定的IBlockRWer.PieceSize自动计算读入数据片数量。返回数据块和块编号。
%[text] 
%[text] [Data,BlockIndex]=obj.LocalReadBlock(ReadSize=ReadSize);
%[text] %读入不超过指定数目的数据片。在此上限范围内尽量读取直到读完。
%[text] 
%[text] [Data,BlockIndex,ObjectIndex,ObjectData]=obj.LocalReadBlock(___,LastObjectIndex=LastObjectIndex);
%[text] %如果处理过程依赖对象特定的数据，即IBlockRWer.ProcessData，则需额外指定LastObjectIndex。第一次调用指定0，将额外返回当前对象序号ObjectIndex和对象特定数据ObjectData。调用方应当保存
%[text] % ObjectData供同一对象内部的所有块重复使用。下次调用LocalReadBlock时，将LastObjectIndex指定为上次调用返回的ObjectIndex。如果返回的ObjectIndex与输入的LastObjectIndex相同，说明数据块仍从
%[text] % 同一对象读入，之前保存的ObjectData可以复用；如果不同，说明数据块来自不同的对象，必须更新ObjectData。
%[text] %该语法可与上述任意语法组合使用。
%[text] 
%[text] [___]=obj.LocalReadBlock(Flags,___);
%[text] %指定额外功能旗帜，可与上述任意语法组合使用。
%[text] ```
%[text] ## 示例
%[text] ```matlabCodeExample
%[text] function Example(obj,Memory,BlockProcess)
%[text] ObjectIndex=0;
%[text] [Data,BlockIndex,NewOI,NewOD]=obj.LocalReadBlock(ReadBytes=Memory,LastObjectIndex=ObjectIndex);
%[text] while ~ismissing(Data)
%[text] 	if NewOI>ObjectIndex
%[text] 		ObjectIndex=NewOI;
%[text] 		ObjectData=NewOD;
%[text] 	end
%[text] 	varargout=cell(1,nargout);
%[text] 	[varargout{:}]=BlockProcess(Data{:},ObjectData{:});
%[text] 	obj.LocalWriteBlock(varargout,BlockIndex);
%[text] 	[Data,BlockIndex,NewOI,NewOD]=obj.LocalReadBlock(ReadBytes=Memory,LastObjectIndex=ObjectIndex);
%[text] end
%[text] ```
%[text] ## 输入参数
%[text] Flags(1,1)ParallelComputing.Flags，指定额外功能旗帜。目前仅支持ForGpu，表示此次读入的数据将交给GPU处理。输入此参数以确保返回的数据不至于超出GPU数组元素个数限制：intmax('int32')
%[text] ## 名称值参数
%[text] ReadBytes(1,1)，建议读入的字节数。因为读入以数据片为最小单位，实际读入的字节数是数据片字节数的整倍，读入数据片的个数为建议字节数/数据片字节数，向下取整。输入的这个建议字节数通常应根据内存决定。
%[text] ReadSize(1,1)，建议读入的数据片数。如果指定此参数，不能指定ReadBytes。
%[text] LastObjectIndex(1,1)，上次调用返回的ObjectIndex，用于判断本次读入的对象跟上次是否相同。如果是第一次调用，指定为0。如果实现IBlockRWer的子类没有指定ProcessData属性的值，无需指定此参数。
%[text] ## 返回值
%[text] Data，读写器返回的数据块。实际读入操作由读写器实现，因此实际数据块大小不一定符合要求。BlockRWStream只对读写器提出建议，不检查其返回值。此外，如果所有文件已读完，将返回missing。
%[text] BlockIndex(1,1)double，数据块的唯一标识符。执行完计算后应将结果同此标识符一并返还给BlockRWStream.LocalWriteBlock，这样才能实现正确的结果收集和写出。如果所有文件已读完，将返回missing，可用ismissing判断是否应该结束计算线程。
%[text] ObjectIndex(1,1)double，本次读取数据块的来源对象。调用方应当保存该值供下次调用使用。如果该值与上次返回的不同，说明读取到了与上次不同的对象，应当更新ObjectData。
%[text] ObjectData，本次读取数据块来源的对象特定数据。仅当ObjectIndex\>LastObjectIndex时该返回值有效，否则为missing。调用方应当保存该数据，在不同数据块之间重复使用，直到读入下一个数据对象。
%[text] **See also** [ParallelComputing.BlockRWStream.LocalWriteBlock](<matlab:doc ParallelComputing.BlockRWStream.LocalWriteBlock>) [ParallelComputing.BlockRWStream.RemoteReadBlock](<matlab:doc ParallelComputing.BlockRWStream.RemoteReadBlock>) [intmax](<matlab:doc intmax>)
function [Data,BlockIndex,ObjectIndex,ObjectData]=LocalReadBlock(obj,Flags,options)
arguments
	obj
	Flags=ParallelComputing.Flags.NoFlags
	options.ReadBytes
	options.ReadPieces
	options.LastObjectIndex
	options.ReturnQueue
end
import ParallelComputing.Exception
if ~isempty(obj.WatchDog)
	obj.WatchDog.stop;
	obj.WatchDog.start;
end
HasFields=ismember(["ReadBytes","ReadPieces","LastObjectIndex","ReturnQueue"],fieldnames(options));
if HasFields(1)
	if HasFields(2)
		Exception.Can_only_specify_ReadBytes_xor_ReadPieces.Throw;
	end
else
	if ~HasFields(2)
		Exception.ReadBytes_xor_ReadPieces_must_specify_one.Throw;
	end
end
if obj.ObjectsRead<obj.NumObjects
	ObjectIndex=obj.ObjectsRead+1;
	Reader=obj.ObjectTable.RWer{ObjectIndex};
	if HasFields(1)
		EndPiece=floor(options.ReadBytes/Reader.PieceSize);
	else
		EndPiece=options.ReadPieces;
	end
	EndPiece=min(obj.PiecesRead+EndPiece,Reader.NumPieces);
	StartPiece=obj.PiecesRead+1;
	if StartPiece>EndPiece
		if HasFields(4)
			options.ReturnQueue.send({Exception.ReadSize_is_smaller_than_IBlockRWer_PieceSize});
			return
		else
			Exception.ReadSize_is_smaller_than_IBlockRWer_PieceSize.Throw('如果使用SpmdRun时出现此错误，可能需要考虑禁用低内存的GPU设备，或减少RuntimeCost');
		end
	end
	if Flags==ParallelComputing.Flags.NoFlags
		[Data,PiecesRead]=Reader.Read(StartPiece,EndPiece);
	else
		[Data,PiecesRead]=Reader.Read(StartPiece,EndPiece,Flags);
	end
	if ~ismissing(PiecesRead)
		EndPiece=StartPiece+PiecesRead-1;
	end
	obj.BlocksRead=obj.BlocksRead+1;
	BlockIndex=obj.BlocksRead;
	if HasFields(3)
		if ObjectIndex>options.LastObjectIndex
			ObjectData=Reader.ProcessData;
		else
			ObjectData=missing;
		end
		if HasFields(4)
			options.ReturnQueue.send({Exception.Operation_succeeded,Data,BlockIndex,ObjectIndex,ObjectData});
		end
	elseif HasFields(4)
		options.ReturnQueue.send({Exception.Operation_succeeded,Data,BlockIndex});
	end
	obj.ObjectTable.BlocksRead(ObjectIndex)=obj.ObjectTable.BlocksRead(ObjectIndex)+1;
	obj.BlockTable(obj.BlocksRead,["ObjectIndex","StartPiece","EndPiece"])={ObjectIndex,StartPiece,EndPiece};
	if EndPiece<Reader.NumPieces
		obj.PiecesRead=EndPiece;
	else
		obj.ObjectsRead=ObjectIndex;
		obj.NextObject;
	end
elseif HasFields(3)
	[Data,BlockIndex,ObjectIndex,ObjectData]=deal(missing);
	if HasFields(4)
		options.ReturnQueue.send({Exception.All_objects_have_been_read,Data,BlockIndex,ObjectIndex,ObjectData});
	end
else
	[Data,BlockIndex]=deal(missing);
	if HasFields(4)
		options.ReturnQueue.send({Exception.All_objects_have_been_read,Data,BlockIndex});
	end
end
end

%[appendix]{"version":"1.0"}
%---
