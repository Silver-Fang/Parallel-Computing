classdef RemoteFunctionHandle<handle
	%远程调用句柄。无论在哪个线程上调用，都会在创建对象的线程上执行
	%在并行计算中，常常会遇到某些资源只接受单线程访问的情况。其它线程不能直接操作该资源，只能向资源线程发出请求，资源线程负责调度执行。
	%本类可以将一个再资源线程上执行的函数句柄包装成一个对象发送到计算线程。计算线程Invoke此对象，就可以令资源线程执行该函数，实现远程调用。
	%```
	% %本例中，主线程持有一个无法一次性载入内存的100㎇大文件。文件只能单线程访问，分多个1㎇的数据块读入内存然后由并行线程执行计算，因此主线程需要不断按照并行线程的要求读取文件。
	% Fid=fopen('100㎇BigFile.bin');
	% BlockSize=bitshift(1,30);
	% ReadFun=ParallelComputing.RemoteFunctionHandle(@()fread(Fid,BlockSize));
	% %Fid是主线程独占的资源，其它线程无法通过该Fid访问文件，因此该函数句柄只能在主线程执行。但是通过RemoteFunctionHandle包装后，可以被并行线程调用。
	% parfor B=1:100
	%	Data=ReadFun.Invoke;
	%	%并行线程调用ReadFun，向主线程请求读取文件，然后返回给并行线程。如果多线程同时调用ReadFun，主线程会自动对请求进行排序。这个顺序是运行时动态确定的，请勿对顺序做出任何假定。
	% end
	%```
	%RemoteFunctionHandle只会在创建它的线程上实际执行函数，无法转移到其它线程执行。此外，请避免嵌套使用RemoteFunctionHandle，否则可能陷入线程互相等待的死锁。
	%并行线程运行期间，请确保主线程仍保有RemoteFunctionHandle的原本，特别是在函数内调用parfeval，但不在本函数内等待其完成的时候。例如，以下操作将会失败：
	%```
	% RunTask(fopen('100㎇BigFile.bin'));
	% %%
	% function RunTask(Fid)
	% BlockSize=bitshift(1,30);
	% ReadFun=ParallelComputing.RemoteFunctionHandle(@()fread(Fid,BlockSize));
	% parfeval(@ProcessData,1,ReadFun);
	% end
	% %RunTask不等待parfeval执行完毕就返回了，主线程上的ReadFun是RunTask的局部变量，RunTask返回后ReadFun就被销毁，主线程将不再能接收到请求。
	% %%
	% function ProcessData(ReadFun)
	% pause(10);
	% Data=ReadFun.Invoke; %此调用永远不会返回，因为主线程上的ReadFun被销毁了。
	% end
	%```
	%对于上例，可以将ReadFun返回以避免它被销毁：
	%```
	% ReadFun=RunTask(fopen('100㎇BigFile.bin'));
	% %%
	% function ReadFun=RunTask(Fid)
	% BlockSize=bitshift(1,30);
	% ReadFun=ParallelComputing.RemoteFunctionHandle(@()fread(Fid,BlockSize));
	% parfeval(@ProcessData,1,ReadFun);
	% end
	% %ReadFun作为返回值而不被销毁，主线程继续持有。
	% %%
	% function ProcessData(ReadFun)
	% pause(10);
	% Data=ReadFun.Invoke; %此调用可以正常返回
	% end
	%```
	%此外，还支持异步调用InvokeAsync方法，其原理类似于parfeval，详见该方法的文档。

	%% 服务端
	properties(GetAccess=private,SetAccess=immutable,Transient)
		FunctionHandle
	end
	properties(GetAccess=private,SetAccess=immutable)
		InvokeQueue parallel.pool.DataQueue
	end
	methods(Access=private)
		function LocalInvoke(obj,Arguments)
			ArgOuts=cell(1,Arguments{1});
			[ArgOuts{:}]=obj.FunctionHandle(Arguments{3:end});
			Arguments{2}.send(ArgOuts);
		end
	end
	methods
		function obj = RemoteFunctionHandle(FunctionHandle)
			%构造函数接受一个function_handle对象作为参数。该函数句柄将使用创建线程的资源执行。
			obj.InvokeQueue=parallel.pool.DataQueue;
			obj.FunctionHandle=FunctionHandle;
			obj.InvokeQueue.afterEach(@LocalInvoke);
		end
	end
	%% 客户端
	methods
		function varargout=Invoke(obj,varargin)
			%向创建线程请求执行函数，并等待返回值。如果没有返回值，该调用将不会等待执行完成。
			%函数的输入输出与原函数句柄完全一致。
			if nargout
				ReturnQueue=parallel.pool.PollableDataQueue;
				obj.InvokeQueue.send([{nargout ReturnQueue} varargin]);
				varargout=ReturnQueue.poll(Inf);
			else
				obj.InvokeQueue.send([{nargout} varargin]);
			end
		end
		function Poller=InvokeAsync(obj,NArgOut,Arguments)
			%异步调用请求。请求不会等待执行完成，而是立刻返回一个parallel.pool.PollableDataQueue，可以等后续实际需要改返回值时再等待。
			%此方法类似于parfeval，可以先请求目标函数在创建线程上开始执行，但并不立即挂起请求线程等待执行完毕，而是允许请求线程继续执行其它任务。等到必须要等待时再行等待。
			% # 语法
			%```
			% %若目标函数没有输入也没有输出：
			% Poller=obj.InvokeAsync;
			%
			% %若目标函数有输出但没有输入：
			% Poller=obj.InvokeAsync(NArgOut);
			%
			% %若目标函数有输入但没有输出：
			% Poller=obj.InvokeAsync(0,Arg1,Arg2,…);
			%
			% %若目标函数既有输入又有输出：
			% Poller=obj.InvokeAsync(NArgOut,Arg1,Arg2,…);
			%```
			% # 参数说明
			% NArgOut：函数返回值的个数
			% Arg1,Arg2,…：输入给函数的参数
			% Poller(1,1)parallel.pool.PollableDataQueue，可等待的数据队列。使用此对象的poll方法可以等待目标函数返回。所有返回值都将排列在元胞行向量中返回。
			% # 示例
			%```
			% Fid=fopen('100㎇BigFile.bin');
			% BlockSize=bitshift(1,30);
			% ReadFun=ParallelComputing.RemoteFunctionHandle(@()fread(Fid,BlockSize));
			% parfor B=1:100
			%	Poller=ReadFun.InvokeAsync(1); %此请求会立刻返回，而不等待主线程上数据块读取完成。
			%	%此时可以执行一些准备工作，与主线程上的数据读取并行执行，直到这样一个阶段，即不取得数据块就无法继续工作时：
			%	[Data,Success]=Poller.poll(100);
			%	%如果数据读取完毕，将立刻返回；若未读取完毕，则等待最多100秒，直到读取完毕再返回。这个时间默认为0，最长Inf，详见parallel.pool.PollableDataQueue.poll文档
			%	if Success
			%		%Success标志指示是否在限定时间内返回了数据。若成功，则可以处理数据
			%	else
			%		error('未在限定时间内返回数据');
			%	end
			% end
			%```
			%See also parallel.pool.PollableDataQueue.poll
			arguments
				obj
				NArgOut=0
			end
			arguments(Repeating)
				Arguments
			end
			Poller=parallel.pool.PollableDataQueue;
			obj.InvokeQueue.send([{NArgOut Poller} Arguments]);
		end
	end
end