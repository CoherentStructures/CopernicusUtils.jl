function loadEarthMap(nat_earth_path)
    natearth= Images.load(nat_earth_path)
    ULpixel = [-179.98888888888889, 89.98888888888889]
    pixelSpacing = 0.02222222222222
    nLon = range(ULpixel[2], step=-1 * pixelSpacing, length=size(natearth)[1])
    nLat = range(ULpixel[1], step=pixelSpacing, length=size(natearth)[2])
    return natearth, nLon,nLat
end
function getLonLat(filename)
     d = NCD.Dataset(filename)
     lon = NCDatasets.nomissing(d["longitude"][:],NaN)[:]
     lat = NCDatasets.nomissing(d["latitude"][:],NaN)[:]
     return lon,lat
end

function getTime(filename)
     d = NCD.Dataset(filename)
     t = d["time"][1]
     return t
end

function loadField(filename,fieldname)
     d = NCD.Dataset(filename)

     U = NCDatasets.nomissing(d[fieldname][:],NaN)[:,:,1]

     t = d["time"][1]
     #TODO: deal with this better
     tdays = round(t - Dates.DateTime(1950,1,1,0,0,0),Dates.Hour
			                       ).value/24.0
     return U,tdays
end

function rescaleUV!!(U,V,Lon,Lat)
	R = 6371e3 # Radius of the Earth in Kilometeres
	n = size(U)[1]
	m = size(U)[2]
	for j in 1:m
	    for i in 1:n
		U[i,j] = sec(deg2rad(Lat[j]))*rad2deg(U[i,j])/R*3600*24
		V[i,j] = rad2deg(V[i,j])/R*3600*24
	    end
	end
end

function read_ocean_velocities(howmany,ww_ocean_data,remove_nan=true,startdate=nothing)
    Lon, Lat = getLonLat(ww_ocean_data * "/" * readdir(ww_ocean_data)[1])
    times = zeros(howmany)
    Us = zeros(length(Lon),length(Lat),howmany)
    Vs = zeros(length(Lon),length(Lat),howmany)
    numfound = 0
    for fname_part in readdir(ww_ocean_data)
    	fname = ww_ocean_data * "/" * fname_part
	if startdate !== nothing
	    if getTime(fname) < startdate
		continue
	    end
	end
    	if numfound >= howmany
    	    break
    	end
	numfound += 1
    	U,t = loadField(fname,"ugos")
    	V,_= loadField(fname,"vgos")
    	rescaleUV!!(U,V,Lon,Lat)
    	times[numfound] = t
    	Us[:,:,numfound] .= U
    	Vs[:,:,numfound] .= V
    end
    if numfound < howmany
	@warn "Only read in $numfound velocities!!"
    end

    sLon = size(Lon)[1]
    sLat = size(Lat)[1]
    stimes = size(times)[1]

    LonS = SharedArray{Float64}(sLon)
    LatS = SharedArray{Float64}(sLat)
    timesS = SharedArray{Float64}(stimes)

    LonS .= Lon
    LatS .= Lat
    timesS .= times

    UsS = SharedArray{Float64}(sLon,sLat,stimes)
    VsS = SharedArray{Float64}(sLon,sLat,stimes)
    Ust1S = SharedArray{Float64}(sLon,sLat,1)

    UsS .= Us
    VsS .= Vs
    Ust1S .= Us[:,:,1:1]



    UsS .= Us
    VsS .= Vs
    Ust1S .= Us[:,:,1:1]


    #Remove NaN values

    if remove_nan
        for t in 1:stimes
            for j in 1:sLat
            	for i in 1:sLon
            	    if isnan(UsS[i,j,t])
                		UsS[i,j,t] = 0.0
            	    end
            	    if isnan(Vs[i,j,t])
                		VsS[i,j,t] = 0.0
            	    end
            	end
            end
        end
    end
    return LonS,LatS,UsS,VsS,timesS,Ust1S
end

function read_ssh(howmany,ww_ocean_data,remove_nan=true,startdate=nothing)
    Lon, Lat = getLonLat(ww_ocean_data * "/" * readdir(ww_ocean_data)[1])
    times = zeros(howmany)
    sshs = zeros(length(Lon),length(Lat),howmany)
    numfound = 0
    for fname_part in readdir(ww_ocean_data)
    	fname = ww_ocean_data * "/" * fname_part
	if startdate !== nothing
	    if getTime(fname) < startdate
		continue
	    end
	end
    	if numfound > howmany
    	    break
    	end
	numfound += 1
    	fname = ww_ocean_data * "/" * fname_part
    	ssh,t = loadField(fname,"adt")
    	times[numfound] = t
    	sshs[:,:,numfound] .= ssh
    end

    if numfound < howmany
	@warn "Only read in $numfound sea surface heights!!"
    end

    sLon = size(Lon)[1]
    sLat = size(Lat)[1]
    stimes = size(times)[1]

    LonS = SharedArray{Float64}(sLon)
    LatS = SharedArray{Float64}(sLat)
    timesS = SharedArray{Float64}(stimes)

    LonS .= Lon
    LatS .= Lat
    timesS .= times

    sshsS = SharedArray{Float64}(sLon,sLat,stimes)
    sshst1S = SharedArray{Float64}(sLon,sLat,1)
    sshsS .= sshs
    sshst1S .= sshs[:,:,1:1]


    if remove_nan
        #=
        for j in 1:sLat
            for i in 1:sLon
            	if isnan(sshst1S[i,j])
                        sshsA[i,j,:] .= 0
            	end
            end
        end
        =#

        for t in 1:stimes
            for j in 1:sLat
            	for i in 1:sLon
            	    if isnan(sshsS[i,j,t])
                		sshsS[i,j,t] = 0.0
            	    end
            	end
            end
        end
    end
    return LonS,LatS,sshsS,timesS,sshst1S
end

function getP(foldername; ndays=90, sshs=false,remove_nan=true,start_date=nothing)
    if sshs
        Lon,Lat, ssh_vals,times,sshsT1 = read_ssh(ndays,foldername,remove_nan,start_date)
        Us,Vs = nothing,nothing
    else
        Lon,Lat,Us,Vs,times,Ust1 = read_ocean_velocities(ndays,foldername,remove_nan,start_date)
        ssh_vals  = nothing
    end
    nx = length(Lon)
    ny = length(Lat)
    nt = length(times)
    if !sshs
        res_full = ItpMetadata(nx,ny,nt,SVector{3}([0.0,-90.0,times[1]]), SVector{3}([360.,+90.0,times[end] + times[2] - times[1] ]),
            (Us,Vs),0,0,1)
        return res_full, Ust1, (Lon,Lat,times)
    else
        res_full = ItpMetadata(nx,ny,nt,SVector{3}([0.0,-90.0]), SVector{3}([360.,+90.0]),
            ssh_vals,0,0,1)
        return res_full,sshst1, (Lon,Lat,times)
    end
end

function restrictP(full_data,UR,LL,tspan,flow,ntraj=20,safety_factor=0.2,sshs=false)
    if !sshs
        #Calculate UR_big, LL_big
        xs = range(LL[1],stop=UR[1],length=ntraj)
        ys = range(LL[1],stop=UR[1],length=ntraj)
        grid = SVector{3}.(xs',ys)
        images = map(x->flow(uv_trilinear, x, tspan; p=full_data), grid)
        firstcoord = x->x[1]

        centre = 0.5*(LL + UR)
        toadd = maximum.(abs.(UR_image - centre,LL_image-centre))*safety_factor

        LL_new = centre .- toadd
        UR_new = centre .+ toadd

        #Copy data to new SharedArray

        #make new interpolation metadata

    else
        throw(AssertionError("Not yet implemented"))
    end
end
